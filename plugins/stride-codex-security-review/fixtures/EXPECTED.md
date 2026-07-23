# Expected findings

Smoke-test fixtures for the security-reviewer agent. Each fixture is a small piece of deliberately vulnerable code. Run `security-review` (or dispatch the `security-reviewer` agent directly) against each fixture and confirm the listed finding is produced. False positives or missing findings indicate a prompt regression.

## Fixtures

### Universal vulnerability classes

- [ ] `sql_injection.py` → injection (critical), `cwe: ["CWE-89"]`, `owasp: ["A03:2021"]` — string-concatenated SQL query with HTTP-supplied `username`.
- [ ] `hardcoded_secret.js` → data_exposure (critical), `cwe: ["CWE-798"]`, `owasp: ["A07:2021"]` — Stripe-shaped secret key literal committed to source.
- [ ] `weak_crypto.ex` → crypto (high), `cwe: ["CWE-327"]`, `owasp: ["A02:2021"]` — MD5 used (unsalted) for password hashing.
- [ ] `command_injection.rb` → injection (critical), `cwe: ["CWE-78"]`, `owasp: ["A03:2021"]` — HTTP-supplied `filename` interpolated unescaped into a shell command.

### Agentic vulnerability classes (require file to import an LLM/agent/MCP SDK)

- [ ] `prompt_injection.py` → prompt_injection (critical), `cwe: ["CWE-1427"]`, `owasp: ["A03:2021"]` — Flask handler concatenates HTTP-supplied `question` directly into an OpenAI chat-completions message body. Python ecosystem coverage.
- [ ] `prompt_injection.ts` → prompt_injection (critical), `cwe: ["CWE-1427"]`, `owasp: ["A03:2021"]` — Express handler concatenates HTTP-supplied `q` into an Anthropic Messages prompt. TypeScript ecosystem coverage — same shape, different ecosystem.
- [ ] `tool_abuse.py` → tool_abuse (critical), `cwe: ["CWE-78", "CWE-22"]`, `owasp: ["A01:2021"]` — LangChain agent exposes unrestricted `run_shell` and `read_file` tools to the LLM with no auth, validation, or confirmation gate.
- [ ] `tool_abuse.ts` → tool_abuse (critical), `cwe: ["CWE-22"]`, `owasp: ["A01:2021"]` — MCP server exposes `write_file` / `delete_file` tools accepting arbitrary paths from LLM clients. TypeScript / @modelcontextprotocol/sdk coverage.
- [ ] `vector_store_poisoning.go` → vector_store_poisoning (high), `cwe: ["CWE-915"]`, `owasp: ["A08:2021"]` — HTTP handler embeds user-supplied comment text directly into pgvector without sanitization or source attribution. Go ecosystem coverage.
- [ ] `model_output_execution.py` → model_output_execution (critical), `cwe: ["CWE-95", "CWE-94"]`, `owasp: ["A03:2021"]` — OpenAI chat-completion response passed directly to `exec()` with no AST check, no sandbox, no allow-list. Python ecosystem coverage.
- [ ] `agent_trust_boundary.ts` → agent_trust_boundary (high), `cwe: ["CWE-1427"]`, `owasp: ["A04:2021"]` — researcher-agent output piped into writer-agent prompt with no delimiter, no integrity check, no quarantine. TypeScript / @anthropic-ai/sdk coverage.

### Supply-chain class

- [ ] `Dockerfile.floating_tag` → supply_chain (medium), `cwe: ["CWE-1357"]`, `owasp: ["A06:2021"]` — production-bound container image pinned to floating tag `node:20` instead of an immutable digest.
- [ ] `curl_pipe_sh.sh` → supply_chain (medium), `cwe: ["CWE-494"]`, `owasp: ["A08:2021"]` — installer script pipes `curl` and `wget` output directly into `sh`/`bash` with no signature or checksum verification.
- [ ] `github_workflow_unpinned.yml` → supply_chain (medium), `cwe: ["CWE-1357"]`, `owasp: ["A08:2021"]` — GitHub Actions referencing third-party actions by `@v4` / `@main` floats instead of SHA. GitHub-Actions ecosystem coverage.
- [ ] `gitlab_ci_unpinned.yml` → supply_chain (medium), `cwe: ["CWE-1357"]`, `owasp: ["A08:2021"]` — GitLab CI `include` referencing a remote pipeline by branch/tag. GitLab CI ecosystem coverage — proves the rule is platform-neutral.
- [ ] `supply_chain_lockfile_drift.json` → supply_chain (low), `cwe: ["CWE-1357"]`, `owasp: ["A08:2021"]` — manifest+lockfile pair embedded in one file: `package.json` declares `left-pad` and the historically-compromised `event-stream`, but `package-lock.json` pins neither (manifest updated without regenerating the lockfile). Lockfile-drift sub-rule positive control. Lockfile drift is inherently a two-file comparison, so both files are embedded as a single reviewable unit; severity `low` per the supply-chain rubric (deterministic-build issue unless the drift introduces an unverified new dependency).
- [ ] `supply_chain_typosquat.txt` → supply_chain (low), `cwe: ["CWE-1357"]`, `owasp: ["A08:2021"]` — pip requirements file containing `reqeusts` (typosquat of `requests`) and `python-dateutl` (typosquat of `python-dateutil`) alongside legitimate packages. Typosquat/hallucinated-package sub-rule positive control; severity `low` (heuristic, no registry lookup — `low` for a plain typo per the supply-chain rubric).

### Framework-aware rule packs

- [ ] `android_exported_no_permission.xml` → authorization (high), `cwe: ["CWE-927"]`, `owasp: ["A01:2021"]` — `AndroidManifest.xml` declares an exported `AdminActivity`, `DeleteAccountReceiver` (with `protectionLevel="normal"` permission), and `BackgroundExportService` — all callable from any installed app. Android/Kotlin rule pack.
- [ ] `android_webview_js_interface.kt` → xss_or_code_exec (critical), `cwe: ["CWE-79"]`, `owasp: ["A03:2021"]` — `HelpWebViewActivity` enables JavaScript, adds an `AndroidBridge` JS interface exposing `deleteUserData` / `exportToken`, and loads a URL from `intent.getStringExtra("url")`. Android/Kotlin rule pack.
- [ ] `android_cleartext_traffic.xml` → insecure_config (high), `cwe: ["CWE-319"]`, `owasp: ["A02:2021"]` — `AndroidManifest.xml` `<application>` element has `android:usesCleartextTraffic="true"` and no `android:networkSecurityConfig`. Android/Kotlin rule pack.
- [ ] `android_sharedprefs_token.kt` → data_exposure (high), `cwe: ["CWE-922"]`, `owasp: ["A02:2021"]` — `LoginActivity` writes password / token / apiKey / OAuth refresh+access / app PIN to plain `SharedPreferences` instead of `EncryptedSharedPreferences`. Android/Kotlin rule pack.
- [ ] `android_sqlite_injection.kt` → injection (critical), `cwe: ["CWE-89"]`, `owasp: ["A03:2021"]` — `UserRepository.searchByName` / `deleteById` / `updateRole` interpolate user-controlled strings directly into `rawQuery` and `execSQL` SQL strings. Android/Kotlin rule pack.
- [ ] `android_hostname_verifier_trust_all.kt` → crypto (critical), `cwe: ["CWE-295"]`, `owasp: ["A02:2021"]` — `InsecureHttpsClient` installs an `X509TrustManager` with empty `checkServerTrusted` and a `HostnameVerifier` returning `true` for every host. Android/Kotlin rule pack.
- [ ] `django_mark_safe_xss.py` → xss_or_code_exec (high), `cwe: ["CWE-79"]`, `owasp: ["A03:2021"]` — Django view wraps `request.GET.get("bio")` with `mark_safe`. Django/Python rule pack.
- [ ] `express_xss_reflected.js` → xss_or_code_exec (high), `cwe: ["CWE-79"]`, `owasp: ["A03:2021"]` — Express handlers call `res.send(\`<h1>Results for: ${req.query.q}</h1>...\`)` and `res.send('<p>You said: ' + req.body.message + '</p>')`. Express/Node.js rule pack.
- [ ] `express_command_injection.js` → injection (critical), `cwe: ["CWE-78"]`, `owasp: ["A03:2021"]` — Express handlers call `exec(\`convert ${req.body.path} ...\`)` and `execSync('rm -rf /var/uploads/' + req.query.dir)`. Express/Node.js rule pack.
- [ ] `express_eval.js` → xss_or_code_exec (critical), `cwe: ["CWE-95"]`, `owasp: ["A03:2021"]` — Express handlers run `eval(req.body.expression)`, `new Function('return ' + req.query.formula)`, and `vm.runInNewContext(req.body.script, {})`. Express/Node.js rule pack.
- [ ] `express_mongoose_injection.js` → injection (critical), `cwe: ["CWE-943"]`, `owasp: ["A03:2021"]` — Express handlers call `User.findOne(req.body)` (operator-injection bypass) and `User.find(req.query)` (operator-injection enumeration). Express/Node.js rule pack.
- [ ] `express_prototype_pollution.js` → input_validation (high), `cwe: ["CWE-1321"]`, `owasp: ["A08:2021"]` — Express handlers call `_.merge(config, req.body)` and `_.set(config, req.body.path, req.body.value)` with attacker-controlled keys. Express/Node.js rule pack.
- [ ] `ios_userdefaults_password.swift` → data_exposure (high), `cwe: ["CWE-922"]`, `owasp: ["A02:2021"]` — iOS view controller writes password / authToken / OAuth refresh+access tokens / biometric backup seed into `UserDefaults.standard.set` instead of Keychain Services. iOS/Swift rule pack.
- [ ] `ios_wkwebview_file_access.swift` → xss_or_code_exec (high), `cwe: ["CWE-79"]`, `owasp: ["A03:2021"]` — `WKWebView` configured with `allowFileAccessFromFileURLs` + `allowUniversalAccessFromFileURLs` and a `WKUserContentController` "callNative" bridge that dispatches native actions without origin verification. iOS/Swift rule pack.
- [ ] `ios_ats_arbitrary_loads.plist` → insecure_config (high), `cwe: ["CWE-319"]`, `owasp: ["A02:2021"]` — `Info.plist` contains `NSAppTransportSecurity` with `NSAllowsArbitraryLoads = true` and `NSAllowsArbitraryLoadsInWebContent = true`; no `NSExceptionDomains` allow-list. iOS/Swift rule pack.
- [ ] `ios_url_session_trust_all.swift` → crypto (critical), `cwe: ["CWE-295"]`, `owasp: ["A02:2021"]` — `URLSessionDelegate` auth-challenge handler returns `.useCredential` with `URLCredential(trust: serverTrust)` unconditionally — no `SecTrustEvaluateWithError`, no pinned cert, no host check. iOS/Swift rule pack.
- [ ] `ios_deep_link_no_auth.swift` → authorization (high), `cwe: ["CWE-939"]`, `owasp: ["A01:2021"]` — `application(_:open:options:)` dispatches `transfer`, `delete-account`, and `set-pin` actions parsed from the URL with no Touch ID / Face ID confirmation, no scheme/host verification. iOS/Swift rule pack.
- [ ] `phoenix_raw_xss.ex` → xss_or_code_exec (high), `cwe: ["CWE-79"]`, `owasp: ["A03:2021"]` — Phoenix LiveView renders user-supplied `q` via `Phoenix.HTML.raw`. Phoenix/Elixir rule pack.
- [ ] `phoenix_mass_assignment.ex` → authorization (high), `cwe: ["CWE-915"]`, `owasp: ["A04:2021"]` — Phoenix controller pipes `user_params` into an `Ecto.Changeset.cast/3` whose allow-list is `__MODULE__.__schema__(:fields)`, exposing privileged `:role` and `:is_admin` fields to client write. Phoenix/Elixir rule pack — analog of Rails `params.permit!`. The actual harm is privilege escalation (writing `:is_admin`), so the class is `authorization`, not `input_validation`.
- [ ] `rails_html_safe_xss.rb` → xss_or_code_exec (high), `cwe: ["CWE-79"]`, `owasp: ["A03:2021"]` — Rails controller exposes `params[:comment]` for `.html_safe` rendering in the corresponding view. Rails/Ruby rule pack.
- [ ] `react_dangerously_set_inner_html.jsx` → xss_or_code_exec (high), `cwe: ["CWE-79"]`, `owasp: ["A03:2021"]` — React components use `dangerouslySetInnerHTML={{__html: post.content}}`, `{__html: user.bio}`, and `{__html: c.body}` on attacker-controlled HTML without a sanitizer. React/Next.js rule pack.
- [ ] `nextjs_api_no_auth.ts` → authentication (high), `cwe: ["CWE-306"]`, `owasp: ["A07:2021"]` — Next.js Pages-Router API route handles POST / DELETE / PUT (including self-promotion to admin role) with no `getServerSession`, no `middleware.ts` matcher, no auth helper. React/Next.js rule pack.
- [ ] `nextjs_redirect_user_input.ts` → input_validation (high), `cwe: ["CWE-601"]`, `owasp: ["A01:2021"]` — Next.js middleware calls `NextResponse.redirect(new URL(req.nextUrl.searchParams.get('next')))` and `NextResponse.rewrite(...)` with no host allow-list. React/Next.js rule pack.
- [ ] `react_href_javascript_uri.jsx` → xss_or_code_exec (high), `cwe: ["CWE-79"]`, `owasp: ["A03:2021"]` — React components bind `<a href={user.website}>`, `<a href={link.url}>`, and `<img src={avatar.url}>` to user-supplied URL strings with no scheme allow-list — `javascript:` and `data:` URIs bypass React's auto-escape. React/Next.js rule pack.
- [ ] `nextjs_getserversideprops_leak.tsx` → data_exposure (high), `cwe: ["CWE-200"]`, `owasp: ["A04:2021"]` — `getServerSideProps` returns `process.env.STRIPE_SECRET_KEY`, `DATABASE_URL`, `INTERNAL_API_TOKEN`, and a raw user object with `passwordHash` / `apiToken` / `mfaSecret` as props — serialized into `__NEXT_DATA__` and visible in page source. React/Next.js rule pack.

- [ ] `django_open_redirect.py` → input_validation (high), `cwe: ["CWE-601"]`, `owasp: ["A01:2021"]` — Django view passes `request.GET.get('next')` directly to `HttpResponseRedirect` and `request.POST['return_to']` to `redirect()` with no `url_has_allowed_host_and_scheme` check. Django/Python rule pack.
- [ ] `phoenix_open_redirect.ex` → input_validation (high), `cwe: ["CWE-601"]`, `owasp: ["A01:2021"]` — Phoenix controller uses `redirect(conn, external: params['return_to'])` and `redirect(conn, external: params['continue_url'])` — the `external:` key bypasses same-origin. Phoenix/Elixir rule pack.
- [ ] `rails_open_redirect.rb` → input_validation (high), `cwe: ["CWE-601"]`, `owasp: ["A01:2021"]` — Rails controller calls `redirect_to params[:next], allow_other_host: true` and `redirect_to params[:url], allow_other_host: true` — the explicit override defeats Rails 7+ default same-host gating. Rails/Ruby rule pack.
- [ ] `django_deserialization.py` → xss_or_code_exec (critical), `cwe: ["CWE-502"]`, `owasp: ["A08:2021"]` — Django views consume `pickle.loads(base64.b64decode(request.POST['state']))`, `yaml.load(request.body)` without `SafeLoader`, and `signing.loads(request.GET['t'])` without `max_age`. Django/Python rule pack.
- [ ] `rails_deserialization.rb` → xss_or_code_exec (critical), `cwe: ["CWE-502"]`, `owasp: ["A08:2021"]` — Rails controller consumes `Marshal.load(Base64.decode64(params[:snapshot]))`, `YAML.load(request.body.read)` without `permitted_classes:`, and `YAML.unsafe_load(params[:yaml])`. Rails/Ruby rule pack.
- [ ] `django_ssrf.py` → input_validation (high), `cwe: ["CWE-918"]`, `owasp: ["A10:2021"]` — Django views consume `requests.get(request.GET['url'])`, `urllib.request.urlopen(request.POST['import_url'])`, and `httpx.AsyncClient().get(request.GET['target'])` with no host allow-list. Realistic worst case: AWS IMDS exfiltration via `169.254.169.254`. Django/Python rule pack.
- [ ] `django_drf_mass_assignment.py` → authorization (high), `cwe: ["CWE-915"]`, `owasp: ["A04:2021"]` — DRF `UserSerializer` uses `fields = '__all__'` on a `User` model that includes `:is_staff`, `:is_superuser`, `:role`, and `:owner_id`. Django/Python rule pack — DRF analog of Rails `params.permit!`.
- [ ] `django_insecure_settings.py` → insecure_config (high), `cwe: ["CWE-1004"]`, `owasp: ["A05:2021"]` — production-bound Django settings with `DEBUG = True`, `ALLOWED_HOSTS = ['*']`, `SECURE_SSL_REDIRECT = False`, `SESSION_COOKIE_SECURE = False`, `CSRF_COOKIE_SECURE = False`, and no `SECURE_HSTS_SECONDS`. Django/Python rule pack.
- [ ] `phoenix_token_no_max_age.ex` → authentication (high), `cwe: ["CWE-613"]`, `owasp: ["A07:2021"]` — password-reset controller verifies a `Phoenix.Token` once with no `max_age` opt and once with `max_age: :infinity`. Phoenix/Elixir rule pack.
- [ ] `phoenix_system_cmd_shell.ex` → injection (critical), `cwe: ["CWE-78"]`, `owasp: ["A03:2021"]` — LiveView event handlers run `System.cmd("sh", ["-c", cmd])` and `:os.cmd(charlist ++ user)` with user input interpolated into the shell command string. Phoenix/Elixir rule pack.
- [ ] `phoenix_liveview_upload.ex` → input_validation (high), `cwe: ["CWE-434"]`, `owasp: ["A04:2021"]` — LiveView `allow_upload(:avatar, accept: :any)` with no `max_file_size:` cap; `consume_uploaded_entries` writes the upload to a publicly served path using the client-supplied filename. Phoenix/Elixir rule pack.
- [ ] `rails_connection_execute.rb` → injection (critical), `cwe: ["CWE-89"]`, `owasp: ["A03:2021"]` — Rails controller passes `"SELECT ... WHERE status = '#{params[:status]}'"` to `ActiveRecord::Base.connection.execute` and `.exec_query` — direct interpolation, no bind parameters. Rails/Ruby rule pack.
- [ ] `rails_missing_auth.rb` → authentication (high), `cwe: ["CWE-306"]`, `owasp: ["A07:2021"]` — Rails `PostsController` defines `create` / `update` / `destroy` actions without `before_action :authenticate_user!` and without `skip_before_action`. Rails/Ruby rule pack.
- [ ] `rails_json_leak.rb` → data_exposure (high), `cwe: ["CWE-200"]`, `owasp: ["A04:2021"]` — Rails `UsersController` calls `render json: @user`, `render json: @users`, and `render json: current_user` on a `User` model with `password_digest`, `reset_password_token`, `api_token`, `two_factor_secret`, `encrypted_otp_secret` — no `only:` / `except:` / serializer. Rails/Ruby rule pack.

### Web defense-in-depth pack

- [ ] `django_missing_headers.py` → insecure_config (high), `cwe: ["CWE-614"]`, `owasp: ["A05:2021"]` — Django production settings with MIDDLEWARE list omitting SecurityMiddleware, `SESSION_COOKIE_SECURE = False`, `SESSION_COOKIE_HTTPONLY = False`, no `SECURE_HSTS_SECONDS`, no CSP. Asserts the cookie-flags finding at severity high; CSP/HSTS/X-Frame-Options at medium are bonus findings expected on the same file but not gated here.
- [ ] `phoenix_missing_headers.ex` → insecure_config (high), `cwe: ["CWE-614"]`, `owasp: ["A05:2021"]` — Phoenix Endpoint with no `force_ssl`, no `put_secure_browser_headers/2`, and `Plug.Session` opts of `secure: false, http_only: false`. Asserts the cookie-flags finding at severity high; CSP / HSTS / X-Frame-Options at medium are bonus findings expected on the same file but not gated here.

### Negative controls

These fixtures are look-alike-but-safe versions of patterns that should fire elsewhere in the suite. The eval runner asserts ZERO findings on each (any finding produced fails the run). Catching over-firing is the regression these guard against.

- [ ] `phoenix_changeset_safe.ex` → NONE — `cast/3` with explicit `[:email, :name]` allow-list excluding `:role` and `:is_admin`. The Phoenix mass-assignment rule must NOT fire here.
- [ ] `phoenix_fragment_safe.ex` → NONE — `fragment("? = ?", field, ^user_input)` positional-binding form with the `^` pin. The Phoenix Ecto fragment-injection rule must NOT fire here.
- [ ] `rails_html_safe_constant.rb` → NONE — `.html_safe` applied to string literals and an allow-list-keyed lookup table. The Rails `html_safe` XSS rule must NOT fire here.

### Considerations mode (per-consideration mitigation verdicts)

These fixtures exercise the agent's `considerations` input mode: a unified diff paired with a task's `security_considerations` list. Each fixture is a `.diff` file plus a sibling `<stem>.considerations` file holding the considerations list, one per non-empty line (the `.considerations` sidecar is an input, not an independently-registered fixture, so `check_fixtures.sh` excludes it from the file↔row parity glob). The eval runner dispatches the agent in `considerations` mode (`mode: considerations` + the diff + the resolved list) and asserts the ordered `consideration_verdicts[].status` values against the row plus a backing-finding expectation. The grammar is `→ CONSIDERATIONS <s1>,<s2>,…` where each `<si>` ∈ `mitigated | partial | unmitigated` in the same order as the `.considerations` file, followed by `AND finding` (positive control — at least one backing `findings[]` entry expected) or `AND clean` (negative control — zero findings expected). Because `consideration_verdicts` is non-deterministic agent output, there is **no** golden-file (`test/golden/`) coverage for this mode — the assertion lives in `run_eval.sh`, mirroring how the findings fixtures are asserted rather than golden-compared.

- [ ] `considerations/token_logging_unmitigated.diff` → CONSIDERATIONS unmitigated,mitigated AND finding — POSITIVE control: the diff swaps a parameterized query for an f-string built from `request.args`, leaving "input is parameterized" **unmitigated** (with a backing `injection` finding) while the log line still omits the token so "tokens never logged" stays **mitigated**.
- [ ] `considerations/parameterized_query_all_mitigated.diff` → CONSIDERATIONS mitigated,mitigated AND clean — NEGATIVE control: the diff replaces a string-concatenated query and a token-logging call with a parameterized query and a token-free log line, **mitigating** both considerations and introducing no new finding.

### CI/CD pipeline rule pack

- [ ] `ci_cd/github_unpinned.yml` → supply_chain (medium), `cwe: ["CWE-1357"]`, `owasp: ["A08:2021"]` — two unpinned action references (`@v4`, `@main`); third step pinned to a 40-hex SHA must NOT trigger (negative case). GitHub Actions ecosystem.
- [ ] `ci_cd/github_expression_injection.yml` → injection (high), `cwe: ["CWE-94", "CWE-78"]`, `owasp: ["A03:2021"]` — `${{ github.event.issue.title }}` and `${{ github.event.issue.body }}` interpolated into shell `run:` steps. GitHub Actions Rule 5.
- [ ] `ci_cd/gitlab_unpinned.yml` → supply_chain (medium), `cwe: ["CWE-1357"]`, `owasp: ["A08:2021"]` — two `include:` references using branch / tag refs instead of SHA. GitLab CI ecosystem.
- [ ] `ci_cd/circleci_unpinned.yml` → supply_chain (medium), `cwe: ["CWE-1357"]`, `owasp: ["A08:2021"]` — orb references using semver (`@4.1.0`) and `@volatile`; both are mutable. CircleCI ecosystem.
- [ ] `ci_cd/bitbucket_secrets_in_fork.yml` → insecure_config (high) AND insecure_config (high), `cwe: ["CWE-732", "CWE-200"]`, `owasp: ["A05:2021", "A01:2021"]` — pull-request pipeline runs with `deployment: production` (exposes the deploy secret on fork-triggered builds, Rule 3) AND embeds `$BITBUCKET_PR_TITLE` in the same `curl` call that carries `$PRODUCTION_DEPLOY_TOKEN` (Rule 4). Bitbucket Pipelines ecosystem.
- [ ] `ci_cd/azure_unpinned.yml` → supply_chain (medium), `cwe: ["CWE-1357"]`, `owasp: ["A08:2021"]` — Azure Pipelines `resources.repositories` references a template repo by `ref: refs/heads/main` (branch float, not a pinned commit SHA). CI/CD Rule 1. Azure Pipelines ecosystem coverage.
- [ ] `ci_cd/drone_unpinned.yml` → supply_chain (medium), `cwe: ["CWE-1357"]`, `owasp: ["A08:2021"]` — Drone steps reference plugin/images by floating tag (`node:20`, `plugins/docker:latest`, `plugins/slack@main`) instead of an immutable digest. CI/CD Rule 1. Drone ecosystem coverage.
- [ ] `ci_cd/jenkins_unpinned.Jenkinsfile` → supply_chain (medium), `cwe: ["CWE-1357"]`, `owasp: ["A08:2021"]` — Jenkins declarative pipeline loads `@Library('build-shared@main')` from a mutable branch rather than a pinned commit SHA. CI/CD Rule 1. Jenkins ecosystem coverage.
- [ ] `ci_cd/tekton_unpinned.yml` → supply_chain (medium), `cwe: ["CWE-1357"]`, `owasp: ["A08:2021"]` — Tekton resolves a remote Task bundle by floating tag (`git-clone:latest`) and runs a step image by version tag, not an immutable digest. CI/CD Rule 1. Tekton ecosystem coverage.

## How to run the smoke test

1. In a Codex CLI session with the `stride-codex-security-review` plugin installed, `cd` into a clean clone of the `stride-codex-security-review` repo.
2. Stage the fixtures so they appear in `git diff HEAD`:
   ```bash
   touch fixtures/SMOKE_TEST_RUN.flag
   git add fixtures/SMOKE_TEST_RUN.flag
   ```
   (The flag file just gives `git diff` something to anchor against — the fixtures themselves are committed.)
3. Run `security-review fixtures/` and confirm each expected finding appears with the documented vulnerability class and severity.
4. Run `security-review --json fixtures/` and confirm the JSON output parses and matches the same set of findings.

## Full-scan scenario

Full-scan mode (`--full`, added in v1.1.0) reviews whole files rather than hunks. Because every fixture above is deliberately vulnerable code, the expected findings are the **same set** whether they reach the agent through a diff or as whole-file content. The full-scan scenario adds two things to verify on top of the per-fixture rows above: the file-enumeration filters and the human-readable header.

### Invocation

```bash
security-review --full fixtures/
```

This scopes `git ls-files` to `fixtures/`, applies the binary and 256 KiB filters, and dispatches the `security-reviewer` agent in `full_file` mode.

### Expected enumeration result

`git ls-files fixtures/` produces every tracked fixture in this directory (including the `ci_cd/` subdirectory) plus `EXPECTED.md`. All of them are UTF-8 text comfortably under 256 KiB, so all survive the binary and size filters and are handed to the agent. The agent's `summary.files_reviewed` should therefore equal the count of tracked fixtures plus `EXPECTED.md`. **Do not hardcode that number here** — it grows with every fixture added; the per-fixture rows in the sections above are the authoritative expected-finding set.

### Expected per-file findings

The per-fixture rows in the sections above (Universal, Agentic, Supply-chain, the framework packs, CI/CD, Web defense-in-depth, and the negative controls) are the authoritative expected-finding set and apply identically in full-scan mode. The table below is a **representative subset** — the original core fixtures — kept as a quick illustration of the `fixture → severity / class / cwe / owasp` shape:

| Fixture | Severity | vulnerability_class | cwe | owasp | One-line rationale |
|---|---|---|---|---|---|
| `sql_injection.py` | critical | `injection` | `["CWE-89"]` | `["A03:2021"]` | HTTP-supplied `username` concatenated into a raw SQL query. |
| `hardcoded_secret.js` | critical | `data_exposure` | `["CWE-798"]` | `["A07:2021"]` | Stripe-shaped secret key literal committed to source. |
| `weak_crypto.ex` | high | `crypto` | `["CWE-327"]` | `["A02:2021"]` | MD5 (unsalted) used for password hashing. |
| `command_injection.rb` | critical | `injection` | `["CWE-78"]` | `["A03:2021"]` | HTTP-supplied `filename` interpolated unescaped into a shell command. |
| `prompt_injection.py` | critical | `prompt_injection` | `["CWE-1427"]` | `["A03:2021"]` | Flask + OpenAI: user `question` concatenated into chat-completions prompt. |
| `prompt_injection.ts` | critical | `prompt_injection` | `["CWE-1427"]` | `["A03:2021"]` | Express + Anthropic: user `q` concatenated into Messages prompt. |
| `tool_abuse.py` | critical | `tool_abuse` | `["CWE-78", "CWE-22"]` | `["A01:2021"]` | LangChain agent exposes shell + arbitrary file read tools. |
| `tool_abuse.ts` | critical | `tool_abuse` | `["CWE-22"]` | `["A01:2021"]` | MCP server exposes write_file / delete_file with arbitrary paths. |
| `vector_store_poisoning.go` | high | `vector_store_poisoning` | `["CWE-915"]` | `["A08:2021"]` | User comment embedded into pgvector without sanitization. |
| `model_output_execution.py` | critical | `model_output_execution` | `["CWE-95", "CWE-94"]` | `["A03:2021"]` | OpenAI response passed directly to `exec()`. |
| `agent_trust_boundary.ts` | high | `agent_trust_boundary` | `["CWE-1427"]` | `["A04:2021"]` | Researcher → writer agent pipe with no quarantine/delimiter. |
| `EXPECTED.md` | — | — | — | — | **Negative case:** documentation file. The agent must NOT produce a finding here. |

A passing full-scan run:

- `summary.files_reviewed` equals the number of tracked fixtures plus `EXPECTED.md` — count-agnostic; it grows as fixtures are added.
- Every fixture's expected finding (per the per-fixture rows in the sections above) appears under its documented `vulnerability_class` and severity, and `summary.findings_by_severity` is the tally of those findings.
- No finding is reported on `EXPECTED.md` (the negative case).
- The human-readable header carries the `(full scan)` qualifier and reports the current run's totals, e.g. `Security review (full scan) — N findings across M files`.
- The `--json` variant produces the same per-finding JSON document shape as diff mode, with `summary.files_reviewed` reflecting the full-mode file count.
- Each agentic fixture's finding sits under the matching `vulnerability_class` from the agent's "Agentic vulnerability classes" section.

### Regression checks specific to full mode

- **Enumeration regression:** if `summary.files_reviewed` is less than 5, either `git ls-files` is being misused (e.g., a filesystem walk crept back in and is excluding tracked files) or the size cap / binary filter is mis-thresholded.
- **Header regression:** if the header is missing the `(full scan)` qualifier or is reporting M files as a diff-line count, Step 5 of `commands/security-review.md` has lost its mode-aware branching.
- **False-positive regression on docs:** if `EXPECTED.md` produces a finding, the agent prompt's false-positive filter has weakened for prose-only files.
- **Schema drift:** the JSON document shape must be byte-for-byte identical between diff and full modes. The per-finding fields are: `severity`, `file`, `line`, `vulnerability_class`, `cwe`, `owasp`, `description`, `remediation`, `confidence`. Missing any of those fields, or introducing a new top-level key without updating this expectation, is a regression. The `cwe` and `owasp` fields were added in plugin v1.2.0 and must populate per the table above for every concrete finding — empty arrays only for true-defense-in-depth notes where no CWE/OWASP category applies.

## What a regression looks like

- **False positive:** the agent reports a finding on a fixture that is not listed above. Inspect the agent prompt's false-positive filter — did a new class slip in that shouldn't be flagged?
- **Missing finding:** the agent does not produce one of the listed findings. Inspect the agent prompt's vulnerability class list and methodology — did a class get dropped?
- **Wrong class:** the agent flags the issue but under a different `vulnerability_class`. Inspect the class taxonomy — did the enum change?
- **Wrong severity:** the issue is found and classified correctly but the severity does not match. Inspect the severity guidance — did the rubric language change?
- **Wrong or missing CWE/OWASP:** the agent reports the correct vulnerability_class but the `cwe` or `owasp` array doesn't match the expected per-fixture mapping. Inspect the agent prompt's "CWE and OWASP mapping requirements" subsection — was a CWE-ID dropped from the recognised list, or did a category mapping get inverted?
- **Agentic class regression:** the agent flags a `prompt_injection` / `tool_abuse` / `agent_trust_boundary` / `model_output_execution` / `vector_store_poisoning` finding on a file that imports NO LLM/agent/MCP SDK (e.g. a plain Flask handler with no AI imports). The "Agentic vulnerability classes" section's import-signal gate has weakened. Conversely, if the agentic fixtures (e.g. `prompt_injection.py`) produce only the universal-class findings (`injection` instead of `prompt_injection`), the agentic-class enum or detection rubric has been dropped from the agent prompt.
- **Cross-ecosystem coverage regression:** the agent detects a class only when the fixture is in one specific language (e.g. flags `prompt_injection.py` but misses `prompt_injection.ts`). The agentic rule is over-fit to a single ecosystem's SDK syntax — the per-language detection-signal list in the agent prompt has gone stale.
- **MAESTRO mode regression:** `security-review --maestro` against the agentic fixtures should populate `maestro_layer` on every finding (`data-operations` for prompt_injection and vector_store_poisoning, `agent-frameworks` for tool_abuse, `agent-ecosystem` for agent_trust_boundary, `agent-frameworks` or `data-operations` for model_output_execution). If `maestro_layer` is missing on findings when --maestro is set, the agent prompt's "MAESTRO 7-layer classification" subsection has been dropped or the dispatch directive isn't being passed. Conversely, if `maestro_layer` APPEARS on findings when --maestro is NOT set, the opt-in gate has weakened.

A passing smoke test is: all four checkboxes can be filled, no other findings appear, and the JSON output parses cleanly.
