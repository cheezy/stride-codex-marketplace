# Vulnerable Phoenix LiveView: System.cmd with shell wrapper interpreting
# user input.
#
# Trust boundary: phx-value-* input flows into a `System.cmd("sh", ["-c", ...])`
# call where the shell interprets metacharacters. An attacker substitutes
# "; rm -rf /; #" into the filename to execute arbitrary commands.
#
# Expected finding: injection (critical), CWE-78, A03:2021.

defmodule MyAppWeb.ImageConverterLive do
  use Phoenix.LiveView, layout: {MyAppWeb.Layouts, :app}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :result, nil)}
  end

  def handle_event("convert", %{"input" => input, "output" => output}, socket) do
    # Vulnerable: shell wrapper expands metacharacters in `input` and `output`.
    # An attacker sets input="cover.jpg; cat /etc/passwd > public/leak.txt; #"
    # and the second command runs unsupervised.
    cmd = "convert #{input} -resize 200x200 #{output}"
    {result, 0} = System.cmd("sh", ["-c", cmd])

    {:noreply, assign(socket, :result, result)}
  end

  def handle_event("legacy_convert", %{"src" => src}, socket) do
    # Vulnerable: same shape via :os.cmd charlist concatenation.
    result = :os.cmd('convert ' ++ String.to_charlist(src) ++ ' /tmp/out.png')
    {:noreply, assign(socket, :result, to_string(result))}
  end
end
