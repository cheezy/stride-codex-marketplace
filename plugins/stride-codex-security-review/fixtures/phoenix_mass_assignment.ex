# Vulnerable Phoenix mass-assignment fixture.
#
# Trust boundary: HTTP `user_params` from the controller flows into the
# `User.changeset/2` cast block, which uses `__MODULE__.__schema__(:fields)`
# as the allow-list. That allow-list includes :role and :is_admin — privileged
# fields the client must never be allowed to write directly.
#
# Expected finding: input_validation (high) — analog of Rails `params.permit!`.

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

  # Vulnerable: casts every field in the schema, including :role and :is_admin.
  # A request body of `{"user":{"is_admin":true,"role":"superuser"}}` will
  # promote the requester to admin.
  def changeset(user, attrs) do
    user
    |> cast(attrs, __MODULE__.__schema__(:fields))
    |> validate_required([:email])
  end
end
