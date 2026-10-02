#!/usr/bin/env python3
"""Ship a validated Stride batch JSON to the Stride API in ONE process.

Usage:
    python3 lib/ship.py --check-auth              # Step 3 preflight: read auth, POST nothing
    python3 lib/ship.py --check-payload <batch>   # --batch preflight: refuse a file holding the token
    python3 lib/ship.py --preview <batch>         # Step 8.5a: print the tree about to be created
    python3 lib/ship.py <batch.json>              # Steps 9-10: strip, validate, POST, branch, render

On Windows `python3` may be named `python` or `py -3`; the script is the same.

Auth file: $STRIDE_AUTH_FILE if set, else .stride_auth.md at the project root
(git rev-parse --show-toplevel), else .stride_auth.md in the current directory.

Why one script: the stride-ideation-stridify skill's Steps 3, 9 and 10 used to
be separate bash fragments that Codex ran in separate shell calls. Shell state
does not persist between those calls, so the token had to be re-read (or
pasted) for the POST, the fragments put it on curl's command line, and they
needed bash. Here the token lives only in this process's memory and in a pipe
to curl:

  - never on any process's argv (argv is visible to `ps`), never in a file,
    and never in a child's environment (an inherited STRIDE_API_TOKEN is
    dropped from every child's environment);
  - never on stdout or stderr: every response body or curl message printed is
    first scrubbed of the token and of any `Bearer <value>` (a dev server's
    debug error page echoes request headers);
  - the payload goes out with --data-binary from a file, not -d "<json>";
  - every temp file (payload, response, curl stderr) is created mode 600
    under the system temp dir and removed on success, failure and interrupt.

The payload is validated with lib/validate_batch.py before anything is sent.
curl is kept (not urllib) because the production edge rejects Python's
default User-Agent with "error code: 1010".

Exit codes:
  0  shipped (2xx) — including a 2xx whose body could not be rendered, which
     prints a do-not-re-run notice: the batch exists, re-running would create
     it twice. --check-auth / --check-payload: the check passed. --preview:
     the tree was printed.
  1  auth unreadable, payload unpreparable or invalid, payload holds the
     token, transport failure, or non-2xx
  2  usage error
  129/130/131/143  interrupted (HUP/INT/QUIT/TERM); if the POST was in
     flight the batch may exist. SIGKILL cannot be caught: it leaves the temp
     files behind (mode 600) and curl running

The POST is never retried: Stride does not guarantee idempotency on a
partially-failed batch.
"""

import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile


LIB_DIR = os.path.dirname(os.path.abspath(__file__))
PREFIX = "stride-ideation:"
USAGE = (
    f"{PREFIX} usage: ship.py --check-auth | ship.py --check-payload <batch.json>"
    f" | ship.py --preview <batch.json> | ship.py <batch.json>"
)
NOT_RENDERABLE = 3
NO_GOALS = 4
POST_STARTED = False  # set just before curl runs: an interrupt after it may leave a created batch


class Interrupted(BaseException):
    def __init__(self, code: int) -> None:
        super().__init__(code)
        self.code = code


def err(message: str) -> None:
    sys.stderr.write(f"{PREFIX} {message}\n")
    sys.stderr.flush()


def child_env() -> "dict[str, str]":
    """The environment every child runs with: never an inherited token."""
    env = dict(os.environ)
    env.pop("STRIDE_API_TOKEN", None)
    env.pop("STRIDE_API_URL", None)
    env["PYTHONUTF8"] = "1"  # helper output decodes as UTF-8 on every host
    return env


def run_helper(script: str, *args: str, stdout: "object" = subprocess.PIPE, stderr: "object" = None) -> "subprocess.CompletedProcess":
    return subprocess.run(
        [sys.executable, os.path.join(LIB_DIR, script), *args],
        stdout=stdout,
        stderr=stderr,  # by default helper diagnostics go straight to the user; they never carry the token
        env=child_env(),
    )


def project_root() -> "str | None":
    """The git toplevel of the current directory, or None outside a repo."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=child_env(),
        )
    except OSError:
        return None
    top = result.stdout.decode("utf-8", "replace").strip()
    return top if result.returncode == 0 and top else None


def auth_file_path() -> str:
    """$STRIDE_AUTH_FILE, else the project root's .stride_auth.md, else the cwd's.

    The first existing file wins; when neither exists the project-root path is
    reported, so a run from a subdirectory names the file the user expects.
    """
    explicit = os.environ.get("STRIDE_AUTH_FILE")
    if explicit:
        return explicit
    candidates = []
    top = project_root()
    if top:
        candidates.append(os.path.join(top, ".stride_auth.md"))
    candidates.append(os.path.join(os.getcwd(), ".stride_auth.md"))
    for path in candidates:
        if os.path.isfile(path):
            return path
    return candidates[0]


def parse_auth(stdout: bytes) -> "tuple[str, str]":
    """(url, token) from read_auth.py's shell-quoted output; "" when absent."""
    values = {}
    for line in stdout.decode("utf-8", "replace").splitlines():
        name, _, quoted = line.partition("=")
        try:
            parts = shlex.split(quoted) if quoted else []
        except ValueError:
            parts = []  # never echo the line: it may hold the token
        values[name] = parts[0] if len(parts) == 1 else ""
    return values.get("STRIDE_API_URL", ""), values.get("STRIDE_API_TOKEN", "")


def read_auth() -> "tuple[str, str, str]":
    """Return (auth_file, url, token) via lib/read_auth.py, or exit 1.

    read_auth.py's stdout (the token) reaches this process through a pipe;
    its stderr is engineered to never contain the token and is shown as-is.
    """
    path = auth_file_path()
    result = run_helper("read_auth.py", path)
    if result.returncode != 0:
        err(f"failed to read auth from {path}")
        sys.exit(1)
    url, token = parse_auth(result.stdout)
    if not url or not token:
        err(f"failed to read auth from {path}")
        sys.exit(1)
    return path, url, token


def quiet_token() -> str:
    """The configured token for scrubbing only, or "" — never exits, prints nothing."""
    result = run_helper("read_auth.py", auth_file_path(), stderr=subprocess.DEVNULL)
    return parse_auth(result.stdout)[1] if result.returncode == 0 else ""


def holds_token(path: str, token: str) -> bool:
    """True when the file carries the token, however its JSON spells it.

    Checks the raw bytes for the literal and \\/-escaped forms, and - when the
    file parses as JSON - the decoded text too, so a token written with \\u
    escapes is caught before anything decodes and prints it.
    """
    with open(path, "rb") as fp:
        body = fp.read()
    forms = {token.encode(), token.replace("/", "\\/").encode()}
    if any(form in body for form in forms):
        return True
    try:
        decoded = json.dumps(json.loads(body), ensure_ascii=False)
    except (ValueError, RecursionError):
        return False
    return token in decoded


def scrub(body: bytes, token: str) -> bytes:
    """Replace every credential in BODY with [REDACTED].

    Covers the token itself, also JSON-escaped (\\/) or percent-encoded in
    either hex case; anything shaped like a Stride token (which also catches a
    truncated echo); and the value of any "Bearer <value>".
    """
    if token:
        parts = []
        for ch in token:
            alts = [re.escape(ch.encode())]
            if not ch.isalnum() and ch != "_":
                alts.append(b"%%%02X" % ord(ch))
                alts.append(b"%%%02x" % ord(ch))
            if ch == "/":
                alts.append(rb"\\/")
            parts.append(b"(?:" + b"|".join(alts) + b")")
        body = re.sub(b"".join(parts), b"[REDACTED]", body)
    body = re.sub(rb"stride_[a-z]{2,10}_[A-Za-z0-9+/=%\\_.-]{8,}", b"[REDACTED]", body)
    body = re.sub(rb"(?i)(bearer(?:\s|%20|&nbsp;)+)[^\s\x22\x27<>]+", rb"\1[REDACTED]", body)
    return body


def print_scrubbed(path: str, token: str) -> None:
    with open(path, "rb") as fp:
        body = fp.read()
    sys.stderr.flush()
    sys.stderr.buffer.write(scrub(body, token))
    sys.stderr.buffer.flush()


def render(path: str) -> "tuple[int, str]":
    """Build the created-identifier table in full, or report why not.

    The server answers {"success": true, "total": N, "goals": [{"goal": {...},
    "child_tasks": [...]}, ...]}. Older and test responses put identifier /
    title / tasks directly on each goal entry and may wrap everything in
    "data". Accept both; anything else is unrenderable.
    """
    try:
        with open(path, "r", encoding="utf-8") as fp:
            data = json.load(fp)
    except (OSError, ValueError):
        return NOT_RENDERABLE, ""
    container = data.get("data", data) if isinstance(data, dict) else None
    goals = container.get("goals") if isinstance(container, dict) else None
    if not isinstance(goals, list):
        return NOT_RENDERABLE, ""
    if not goals:
        return NO_GOALS, ""

    def ident(item: "object") -> "str | None":
        value = item.get("identifier") if isinstance(item, dict) else None
        return value if isinstance(value, str) and value else None

    lines = ["", "Created goals and tasks:", ""]
    for entry in goals:
        if not isinstance(entry, dict):
            return NOT_RENDERABLE, ""
        goal = entry["goal"] if isinstance(entry.get("goal"), dict) else entry
        tasks = entry.get("child_tasks", entry.get("tasks")) or []
        if not isinstance(tasks, list) or ident(goal) is None:
            return NOT_RENDERABLE, ""
        lines.append(f"  {ident(goal):>6}  {goal.get('title') or '(no title)'}")
        for task in tasks:
            if ident(task) is None:
                return NOT_RENDERABLE, ""
            lines.append(f"  {ident(task):>6}    {task.get('title') or '(no title)'}")
    lines.append("")
    return 0, "\n".join(lines)


def new_temp(temps: "list[str]") -> str:
    """Create a mode-600 temp file under the system temp dir and track it."""
    try:
        fd, path = tempfile.mkstemp(prefix="stride-ideation-ship.")
    except OSError:
        err(f"could not create a temp file in {tempfile.gettempdir()}; nothing was sent")
        sys.exit(1)
    temps.append(path)
    os.close(fd)
    if os.name != "nt":
        os.chmod(path, 0o600)
    return path


def check_auth() -> int:
    path, url, _token = read_auth()
    print(
        f"{PREFIX} auth file OK — read from {path} (API URL {url}). "
        f"The token is checked by the server only when the batch is POSTed."
    )
    return 0


def require_file(batch_path: str) -> None:
    if not os.path.isfile(batch_path):
        err(f"batch JSON not found at {batch_path}")
        sys.exit(1)


def check_payload(batch_path: str) -> int:
    """Refuse a batch file that carries the configured token anywhere in it.

    Run before the --batch preview prints the file, so a pasted batch holding
    the token is stopped before it reaches the screen. Sends nothing.
    """
    require_file(batch_path)
    _path, _url, token = read_auth()
    if holds_token(batch_path, token):
        err(
            f"{batch_path} contains the configured Stride API token; nothing was "
            f"sent. Remove it from the file and retry."
        )
        return 1
    return 0


def preview(batch_path: str) -> int:
    """Print the goal/task tree a batch would create, from the file alone.

    Step 8.5a's preview. Reads only the on-disk batch JSON — never auth — and
    sends nothing. No identifiers exist yet: the API assigns them on POST.
    """
    require_file(batch_path)
    try:
        with open(batch_path, "r", encoding="utf-8") as fp:
            data = json.load(fp)
    except (OSError, ValueError) as exc:
        err(f"could not read {batch_path}: {exc}")
        return 1
    goals = data.get("goals") if isinstance(data, dict) else None
    if not isinstance(goals, list):
        err(f"{batch_path} has no 'goals' array to preview")
        return 1
    notes = data.get("decomposition_notes", "")
    lines = ["", "Goals and tasks to be created:", ""]
    for goal in goals:
        goal = goal if isinstance(goal, dict) else {}
        tasks = goal.get("tasks", []) or []
        tasks = tasks if isinstance(tasks, list) else []
        n = len(tasks)
        lines.append(f"  Goal: {goal.get('title', '(no title)')}  ({n} task{'s' if n != 1 else ''})")
        for task in tasks:
            title = task.get("title", "(no title)") if isinstance(task, dict) else "(no title)"
            lines.append(f"    - {title}")
    lines.append("")
    if notes:
        lines += ["Cross-goal claim order:", f"  {notes}", ""]
    print("\n".join(lines))
    return 0


def post(batch_path: str, temps: "list[str]") -> int:
    require_file(batch_path)

    # (9a) Strip the local-audit fields into a mode-600 temp file. This runs
    # before auth is read, so no child holds the token. The on-disk batch JSON
    # is not modified.
    payload = new_temp(temps)
    with open(payload, "wb") as out:
        stripped = run_helper("strip_audit_fields.py", batch_path, stdout=out)
    if stripped.returncode != 0:
        err(f"failed to prepare API payload from {batch_path}")
        return 1
    # Validate the exact bytes about to be sent: the file on disk may have
    # changed since the skill validated and previewed it (e.g. --batch, where
    # those are separate steps). Advisory warnings were already shown there.
    # Only the fatal diagnostic is surfaced: the advisory warnings were shown
    # at that earlier step and would otherwise bury the response body below.
    validated = subprocess.run(
        [sys.executable, os.path.join(LIB_DIR, "validate_batch.py"), payload],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        env=child_env(),
    )
    if validated.returncode != 0:
        # The validator echoes some batch content (unexpected root keys, a
        # goal's type, a dependency value), and that content is user-editable:
        # scrub it before it reaches the screen, since the token screen below
        # has not run yet.
        fatal = b"".join(
            line for line in validated.stderr.splitlines(keepends=True)
            if not line.startswith(f"{PREFIX} warning:".encode())
        )
        sys.stderr.flush()
        sys.stderr.buffer.write(scrub(fatal, quiet_token()))
        sys.stderr.buffer.flush()
        err(f"{batch_path} failed validation; nothing was sent")
        return 1

    response = new_temp(temps)
    curl_err = new_temp(temps)
    curl = shutil.which("curl")
    if curl is None:
        err("curl was not found on PATH; nothing was sent. Install curl (it ships with Windows 10+, macOS and most Linux distributions).")
        return 1

    _auth, url, token = read_auth()

    # Refuse to send the configured token as task content: a pasted recovery
    # transcript or a decomposer that read the wrong file could carry it into
    # the batch, which is POSTed where every board member can read it.
    if holds_token(payload, token):
        err(
            f"the batch contains the configured Stride API token; nothing was "
            f"sent. Remove it from {batch_path} and retry."
        )
        return 1

    # (9b) The Authorization header reaches curl as a config on its stdin
    # (-K -): no argv, no file. -q must come first so ~/.curlrc cannot switch
    # on --verbose/--trace; -g stops a {} or [] in the URL from expanding into
    # more than one POST. Never -v.
    escaped = token.replace("\\", "\\\\").replace('"', '\\"')
    config = f'header = "Authorization: Bearer {escaped}"\n'.encode()
    global POST_STARTED
    POST_STARTED = True
    with open(curl_err, "wb") as err_fp:
        result = subprocess.run(
            [
                curl, "-q", "-g", "-sS", "-X", "POST",
                "-K", "-",
                "-H", "Content-Type: application/json",
                "--data-binary", f"@{payload}",
                "-o", response,
                "-w", "%{http_code}",
                f"{url.rstrip('/')}/api/tasks/batch",
            ],
            input=config,
            stdout=subprocess.PIPE,
            stderr=err_fp,
            env=child_env(),
        )
    del config, escaped
    http_code = result.stdout.decode("utf-8", "replace").strip()

    if result.returncode != 0 or not http_code or http_code == "000":
        err("HTTP request failed before the Stride API responded:")
        if os.path.getsize(curl_err) > 0:
            print_scrubbed(curl_err, token)
        else:
            err(f"  curl exited with status {result.returncode} and no stderr output.")
        return 1

    # (9c) Every non-2xx prints the response body verbatim (token-scrubbed)
    # and exits non-zero.
    if not http_code.startswith("2"):
        if http_code.startswith("4"):
            err(f"Stride API rejected the batch (HTTP {http_code}). Response body:")
        elif http_code.startswith("5"):
            err(f"Stride API returned HTTP {http_code}. Response body:")
        else:
            err(f"unexpected HTTP status {http_code}. Response body:")
        print_scrubbed(response, token)
        sys.stderr.write("\n")
        return 1

    # (10) Render the created identifiers. The table is built in full before
    # anything is printed, so an unexpected shape never leaves half a table.
    rc, table = render(response)
    if rc == 0:
        print(table)
        print("Batch shipped successfully.")
        print("The goals are now visible in the Stride workspace's Backlog column.")
        return 0

    if rc == NO_GOALS:
        err(
            f"Stride answered HTTP {http_code} but listed no created goals. Check "
            f"the Stride workspace's Backlog column before re-running. Response body:"
        )
    else:
        err(
            f"the batch was created (HTTP {http_code}), but the response could not "
            f"be rendered — do NOT re-run stride-ideation-stridify: the goals already "
            f"exist in Stride and a second run would create them twice."
        )
        err("check the Stride workspace's Backlog column for the created identifiers. Response body:")
    print_scrubbed(response, token)
    sys.stderr.write("\n")
    return 0


def main(argv: "list[str]") -> int:
    if len(argv) == 2 and argv[1] == "--check-auth":
        return check_auth()
    if len(argv) == 3 and argv[1] == "--check-payload" and not argv[2].startswith("-"):
        return check_payload(argv[2])
    if len(argv) == 3 and argv[1] == "--preview" and not argv[2].startswith("-"):
        return preview(argv[2])
    if len(argv) != 2 or argv[1].startswith("-"):
        sys.stderr.write(USAGE + "\n")
        return 2

    temps: "list[str]" = []
    try:
        return post(argv[1], temps)
    finally:
        for path in temps:
            try:
                os.remove(path)
            except OSError:
                pass


def raise_interrupted(code: int):
    def handler(_signum, _frame):
        raise Interrupted(code)
    return handler


def interrupted(code: int) -> int:
    if POST_STARTED:
        err(
            "interrupted; if the POST was in flight the batch may already exist "
            "— check the Stride workspace's Backlog column before re-running."
        )
    return code


if __name__ == "__main__":
    # A title the console code page cannot encode (cp1252 on Windows) must
    # never turn a shipped batch into a traceback and an exit 1 that invites
    # a duplicate re-run.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="backslashreplace")
    # A shell that starts this as a background job hands it SIGINT and SIGQUIT
    # already ignored; install handlers explicitly so every catchable
    # interrupt still cleans up, kills curl and warns.
    signal.signal(signal.SIGINT, signal.default_int_handler)
    signal.signal(signal.SIGTERM, raise_interrupted(143))
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, raise_interrupted(129))
    if hasattr(signal, "SIGQUIT"):
        signal.signal(signal.SIGQUIT, raise_interrupted(131))
    try:
        sys.exit(main(sys.argv))
    except KeyboardInterrupt:
        sys.exit(interrupted(130))
    except Interrupted as exc:
        sys.exit(interrupted(exc.code))
