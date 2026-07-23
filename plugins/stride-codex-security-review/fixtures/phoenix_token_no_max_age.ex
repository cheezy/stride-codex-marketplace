# Vulnerable Phoenix.Token.verify call with no max_age opt.
#
# Trust boundary: an HTTP-supplied password-reset token is verified without
# any age bound. Once a token leaks (logs, browser history, referrer), it
# remains valid forever — the canonical replay vector.
#
# Expected finding: authentication (high), CWE-613, A07:2021.

defmodule MyAppWeb.PasswordResetController do
  use Phoenix.Controller, namespace: MyAppWeb
  import Plug.Conn

  alias MyApp.Accounts

  def edit(conn, %{"token" => token}) do
    # Vulnerable: no max_age opt -> token never expires.
    case Phoenix.Token.verify(MyAppWeb.Endpoint, "password reset", token) do
      {:ok, user_id} ->
        user = Accounts.get_user!(user_id)
        render(conn, :edit, user: user)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid token")
        |> redirect(to: ~p"/sessions/new")
    end
  end

  def update(conn, %{"token" => token, "password" => password}) do
    # Vulnerable: even more dangerous shape — explicit :infinity.
    case Phoenix.Token.verify(MyAppWeb.Endpoint, "password reset", token,
           max_age: :infinity) do
      {:ok, user_id} ->
        Accounts.reset_password(user_id, password)
        redirect(conn, to: ~p"/sessions/new")

      {:error, _} ->
        conn |> put_status(:bad_request) |> render(:edit)
    end
  end
end
