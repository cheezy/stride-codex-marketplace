# Smoke-test fixture: Phoenix/Elixir rule pack — raw() on user-controlled data
#
# A LiveView event handler stores a search term from params and renders it
# back into the page via Phoenix.HTML.raw, disabling the auto-escape that
# would otherwise neutralize any HTML in the input. An attacker submits
# `<script>alert(document.cookie)</script>` as the search term and lands
# stored XSS on every subsequent page render.
defmodule MyAppWeb.SearchLive do
  use Phoenix.LiveView
  import Phoenix.HTML

  def mount(_params, _session, socket), do: {:ok, assign(socket, :search, "")}

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, assign(socket, :search, q)}
  end

  def render(assigns) do
    ~H"""
    <p>You searched for: <%= raw(@search) %></p>
    """
  end
end
