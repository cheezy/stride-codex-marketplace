# Vulnerable Django view: open-redirect via user-controlled URL.
#
# Trust boundary: HTTP-supplied `next` and `return_to` from request.GET / form
# data flow straight into HttpResponseRedirect / redirect() with no host
# allow-list check. After login, an attacker substitutes evil.com to phish.
#
# Expected finding: input_validation (high), CWE-601, A01:2021.

from django.shortcuts import redirect, render
from django.http import HttpResponseRedirect
from django.contrib.auth.decorators import login_required


@login_required
def post_login_redirect(request):
    # Vulnerable: ?next= is consumed verbatim with no host allow-list.
    next_url = request.GET.get("next", "/")
    return HttpResponseRedirect(next_url)


def logout_flow(request):
    if request.method == "POST":
        return redirect(request.POST["return_to"])
    return render(request, "logout.html")
