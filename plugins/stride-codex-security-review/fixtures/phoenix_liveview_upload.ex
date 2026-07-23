# Vulnerable Phoenix LiveView: allow_upload with no accept: filter and no
# max_file_size: cap.
#
# Trust boundary: a remote client uploads arbitrary files of arbitrary type
# and size to the server's local filesystem. The consume_uploaded_entries
# block writes the entry path into priv/static/uploads/ where it is
# directly served — including HTML uploaded as a fake image (stored XSS).
#
# Expected finding: input_validation (high), CWE-434, A04:2021.

defmodule MyAppWeb.AvatarLive do
  use Phoenix.LiveView, layout: {MyAppWeb.Layouts, :app}

  def mount(_params, _session, socket) do
    socket =
      socket
      # Vulnerable: accept: :any allows HTML / JS / EXE / anything. No
      # max_file_size: cap means a client can submit a 100 GB stream.
      |> allow_upload(:avatar, accept: :any)

    {:ok, socket}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("save", _params, socket) do
    paths =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        # Writes the upload to a publicly served directory using the client-
        # supplied filename verbatim. No magic-bytes re-check on the content.
        dest = Path.join("priv/static/uploads", entry.client_name)
        File.cp!(path, dest)
        {:ok, "/uploads/#{entry.client_name}"}
      end)

    {:noreply, assign(socket, :uploaded, paths)}
  end
end
