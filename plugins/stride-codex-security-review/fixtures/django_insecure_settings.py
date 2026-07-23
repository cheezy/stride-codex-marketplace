# Vulnerable Django production settings: DEBUG=True, ALLOWED_HOSTS=['*'],
# missing SECURE_* hardening.
#
# Trust boundary: this is settings/production.py — wired into manage.py for
# production traffic. Production DEBUG leaks stack traces with env vars on
# every 500; wildcard ALLOWED_HOSTS allows Host-header attacks; the missing
# SECURE_* family ships cookies and traffic over plaintext.
#
# Expected finding: insecure_config (high), CWE-1004, A05:2021.

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

# Vulnerable: DEBUG must be False in production.
DEBUG = True

# Vulnerable: wildcard ALLOWED_HOSTS opens Host-header cache poisoning, password
# reset link forging, and the canonical Django CVE-2018-7536-class issue.
ALLOWED_HOSTS = ["*"]

# Vulnerable: missing or False on every SECURE_* flag in a production config.
SECURE_SSL_REDIRECT = False
SESSION_COOKIE_SECURE = False
CSRF_COOKIE_SECURE = False
# SECURE_HSTS_SECONDS is not set at all -> HSTS never emitted.
# SECURE_PROXY_SSL_HEADER is not set -> Django can't detect HTTPS termination.

SECRET_KEY = os.environ.get("SECRET_KEY", "INSECURE-DEFAULT-DO-NOT-USE")

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": "myapp_prod",
        "USER": os.environ.get("DB_USER", "myapp"),
        "PASSWORD": os.environ.get("DB_PASSWORD", ""),
        "HOST": "db.internal",
        "PORT": "5432",
    }
}

INSTALLED_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.auth",
    "myapp",
]

MIDDLEWARE = [
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
]

ROOT_URLCONF = "myapp.urls"
WSGI_APPLICATION = "myapp.wsgi.application"
