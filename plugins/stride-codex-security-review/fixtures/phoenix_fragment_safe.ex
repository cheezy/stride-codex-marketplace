# Negative-control fixture for the Phoenix Ecto fragment injection rule.
#
# This is the SAFE shape: fragment with positional binding (? = ?) and the ^
# pin operator. Ecto's parameterized-binding default is honored. The Phoenix
# fragment-injection rule in agents/security-reviewer.md MUST NOT fire on
# this file.
#
# Expected: zero findings on this file (EXPECTED.md asserts → NONE).

defmodule MyApp.Search do
  import Ecto.Query

  alias MyApp.Accounts.User
  alias MyApp.Repo

  # Safe: lower(?) wraps a column reference, ^lower_term binds a parameterized
  # value. Ecto generates a parameterized SQL query; the user input never enters
  # the SQL string literal. Any attempted "' OR 1=1 --" payload reaches the
  # database as a bound parameter, not as SQL syntax.
  def search_users(term) do
    lower_term = String.downcase(term)

    from(u in User,
      where: fragment("lower(?) LIKE ?", u.email, ^"%#{lower_term}%"),
      order_by: u.email
    )
    |> Repo.all()
  end

  # Also safe: the column reference inside fragment uses ?, with the actual
  # column passed as the second arg, and the value uses ^ (parameterized).
  def find_by_external_id(external_id) do
    from(u in User,
      where: fragment("? = ?", u.external_id, ^external_id)
    )
    |> Repo.one()
  end
end
