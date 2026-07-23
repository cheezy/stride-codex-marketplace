# Vulnerable Phoenix Endpoint: missing security headers and weak session cookie config.
#
# Trust boundary: the Endpoint serves authenticated user sessions but force_ssl is
# absent, no put_resp_header pipeline sets CSP / X-Frame-Options, and the
# Plug.Session opts omit secure: true and http_only: true.
#
# Expected findings (defense-in-depth pack):
#   - missing CSP                  insecure_config (medium)
#   - missing HSTS / force_ssl     insecure_config (medium)
#   - missing X-Frame-Options      insecure_config (medium)
#   - session cookie no secure/http_only  insecure_config (high)

defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  # No force_ssl: [hsts: true] — Strict-Transport-Security never emitted in prod.
  # plug Plug.SSL is also absent. The :url config below carries no `scheme: "https"`
  # default either, so the framework will never reach for HSTS on its own.

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static, at: "/", from: :my_app, gzip: false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  # Session cookie: secure: false, http_only not set, same_site not set.
  # A leaked cookie over a single HTTP request hijacks the session.
  @session_options [
    store: :cookie,
    key: "_my_app_key",
    signing_salt: "REDACTED",
    same_site: nil,
    secure: false,
    http_only: false
  ]
  plug Plug.Session, @session_options

  # No router-side put_resp_header pipeline for Content-Security-Policy,
  # X-Frame-Options, Referrer-Policy, Permissions-Policy. The router's
  # :browser pipeline does NOT call put_secure_browser_headers/2 either —
  # which is Phoenix's built-in default for these headers.
  plug MyAppWeb.Router
end
