# Vulnerable Django view: SSRF via requests.get(user_url).
#
# Trust boundary: HTTP-supplied `url` parameter flows directly into
# requests.get with no host allow-list. The attacker substitutes the AWS
# metadata endpoint (169.254.169.254) to exfiltrate IAM credentials.
#
# Expected finding: input_validation (high), CWE-918, A10:2021.

import requests
import urllib.request
import httpx
from django.http import JsonResponse, HttpResponse


def fetch_preview(request):
    # Vulnerable: full SSRF — attacker substitutes
    #   http://169.254.169.254/latest/meta-data/iam/security-credentials/
    # and the response is returned to them, exfiltrating the AWS IAM role
    # credentials available to this server.
    target = request.GET["url"]
    response = requests.get(target, timeout=5)
    return HttpResponse(response.text, content_type="text/plain")


def import_from_url(request):
    # Vulnerable: same shape but with urllib.
    url = request.POST["import_url"]
    with urllib.request.urlopen(url) as resp:
        body = resp.read()
    return JsonResponse({"bytes_read": len(body)})


async def webhook_proxy(request):
    # Vulnerable: same shape but with httpx async client.
    target = request.GET["target"]
    async with httpx.AsyncClient() as client:
        r = await client.get(target)
    return JsonResponse({"status": r.status_code, "body": r.text})
