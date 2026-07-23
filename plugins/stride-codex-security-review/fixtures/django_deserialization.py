# Vulnerable Django view: unsafe deserialization of HTTP-supplied data.
#
# Trust boundary: HTTP request body / cookie / form value flows into
# pickle.loads, yaml.load (without SafeLoader), and django.core.signing.loads
# without max_age. All three are remote-code-execution sinks.
#
# Expected finding: xss_or_code_exec (critical), CWE-502, A08:2021.

import pickle
import base64

import yaml
from django.core import signing
from django.http import HttpResponse


def import_state(request):
    # Vulnerable: pickle.loads on attacker-controlled bytes -> arbitrary
    # __reduce__ payload -> RCE.
    blob = base64.b64decode(request.POST["state"])
    state = pickle.loads(blob)
    return HttpResponse(f"Imported {state.get('name')}")


def parse_config(request):
    # Vulnerable: yaml.load without Loader=SafeLoader resolves !!python/object
    # tags that execute code at parse time.
    raw = request.body.decode("utf-8")
    cfg = yaml.load(raw)  # noqa: not yaml.safe_load
    return HttpResponse(f"Loaded {len(cfg)} keys")


def consume_token(request):
    # Vulnerable: signing.loads without max_age accepts forever-replayed tokens
    # produced by signing.dumps. If a token leaked once, it works indefinitely.
    token = request.GET["t"]
    payload = signing.loads(token)
    return HttpResponse(f"OK: {payload}")
