# Vulnerable Phoenix controller: open-redirect via Plug.Conn.redirect external.
#
# Trust boundary: HTTP-supplied `url` and `return_to` from params flow into
# redirect(conn, external: ...) which intentionally bypasses Phoenix's same-
# origin guard. After login, an attacker substitutes evil.com to phish.
#
# Expected finding: input_validation (high), CWE-601, A01:2021.

defmodule MyAppWeb.SessionController do
  use Phoenix.Controller, namespace: MyAppWeb
  import Plug.Conn

  def post_login(conn, %{"return_to" => return_to}) do
    # Vulnerable: external: bypasses same-origin; return_to is user-controlled.
    redirect(conn, external: return_to)
  end

  def oauth_callback(conn, %{"continue_url" => url}) do
    # Vulnerable: continue_url is attacker-controllable in the OAuth redirect_uri.
    redirect(conn, external: url)
  end
end
