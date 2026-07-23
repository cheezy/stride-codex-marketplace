# Smoke-test fixture: Django/Python rule pack — mark_safe on user-controlled data
#
# A Django view fetches a user-supplied bio and wraps it with mark_safe
# before rendering. mark_safe is Django's escape-disable marker, the
# analog of Rails .html_safe or Phoenix raw(). Any HTML in `bio` reaches
# the rendered template as live markup. Stored XSS waiting to happen.
from django.shortcuts import render
from django.utils.safestring import mark_safe


def profile(request):
    bio = request.GET.get("bio", "")
    # mark_safe disables Django's auto-escape on this string. Combined
    # with user-controlled input, this is a textbook XSS.
    safe_bio = mark_safe(bio)
    return render(request, "profile.html", {"bio": safe_bio})
