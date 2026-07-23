# Negative-control fixture for the Phoenix mass-assignment rule.
#
# This is the SAFE shape: cast/3 with an explicit allow-list that excludes
# privileged fields (:role, :is_admin). The Phoenix mass-assignment rule
# in agents/security-reviewer.md MUST NOT fire on this file.
#
# Expected: zero findings on this file (EXPECTED.md asserts → NONE).

defmodule MyAppWeb.UserController do
  use Phoenix.Controller, namespace: MyAppWeb
  import Plug.Conn

  alias MyApp.Accounts.User
  alias MyApp.Repo

  def update(conn, %{"id" => id, "user" => user_params}) do
    user = Repo.get!(User, id)

    case user |> User.changeset(user_params) |> Repo.update() do
      {:ok, _user} ->
        redirect(conn, to: "/users/#{id}")

      {:error, changeset} ->
        render(conn, :edit, changeset: changeset)
    end
  end
end

defmodule MyApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, :string
    field :is_admin, :boolean, default: false
    timestamps()
  end

  # Safe: explicit allow-list excludes :role and :is_admin. A request body of
  # {"user":{"is_admin":true,"role":"superuser"}} silently drops those fields.
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> validate_required([:email])
    |> unique_constraint(:email)
  end
end
