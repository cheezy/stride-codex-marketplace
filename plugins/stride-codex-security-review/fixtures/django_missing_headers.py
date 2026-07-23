# Vulnerable Django settings: missing security headers on a production-bound config.
#
# Trust boundary: the entire site serves authenticated user sessions over HTTPS but
# the MIDDLEWARE list omits SecurityMiddleware, SESSION_COOKIE_SECURE is False, no
# SECURE_HSTS_SECONDS is set, no Content-Security-Policy is configured anywhere,
# and X-Frame-Options is silently absent.
#
# Expected findings (defense-in-depth pack):
#   - missing CSP                    insecure_config (medium)
#   - missing HSTS                   insecure_config (medium)
#   - missing X-Frame-Options        insecure_config (medium)
#   - SESSION_COOKIE_SECURE = False  insecure_config (high)  (auth-session cookie)

DEBUG = False
ALLOWED_HOSTS = ["myapp.example.com"]
SECRET_KEY = "REDACTED"

# MIDDLEWARE omits django.middleware.security.SecurityMiddleware AND any
# third-party CSP middleware (django-csp). No header-emitting layer is present.
MIDDLEWARE = [
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
]

# Session cookies are interceptable and JS-readable.
SESSION_COOKIE_SECURE = False
SESSION_COOKIE_HTTPONLY = False
SESSION_COOKIE_SAMESITE = None
CSRF_COOKIE_SECURE = False

# No SECURE_HSTS_* settings at all -> Strict-Transport-Security never emitted.
# (commented out for clarity; in real code these would simply be absent)
# SECURE_HSTS_SECONDS = 0

# No X-Frame-Options policy.
# X_FRAME_OPTIONS is never set; default is SAMEORIGIN only when SecurityMiddleware
# is enabled — and it isn't.

INSTALLED_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.auth",
    "myapp",
]

ROOT_URLCONF = "myapp.urls"
WSGI_APPLICATION = "myapp.wsgi.application"
