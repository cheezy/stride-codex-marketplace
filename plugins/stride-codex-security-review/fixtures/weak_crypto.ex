# Vulnerable fixture: MD5 used to hash passwords at rest.
# DO NOT USE — illustrative only.

defmodule Demo.Accounts do
  @moduledoc false

  # Vulnerability: MD5 is fast, unsalted in this code path, and broken for
  # password hashing. An offline attacker who obtains the users table can
  # crack realistic passwords in seconds with consumer hardware.
  # Trust boundary: any path that loads the users table (backup, log leak,
  # SQL injection elsewhere) gives the attacker the inputs needed.
  def hash_password(password) when is_binary(password) do
    :crypto.hash(:md5, password) |> Base.encode16(case: :lower)
  end

  def verify_password(password, stored_hash) do
    hash_password(password) == stored_hash
  end
end
