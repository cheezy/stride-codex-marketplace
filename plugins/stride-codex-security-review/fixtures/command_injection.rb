# Vulnerable fixture: unescaped shell-out with user input.
# DO NOT USE — illustrative only.

require "sinatra"

# Vulnerability: `filename` comes from an HTTP query parameter and is
# interpolated unescaped into a shell command. Sending
# ?filename=foo.txt;rm -rf / passes attacker-controlled tokens to bash.
# Trust boundary: the HTTP request handler. Sink: backticks / system().
# Worst case: remote code execution as whatever user runs the web app.
get "/preview" do
  filename = params["filename"]
  output = `head -n 20 /var/uploads/#{filename}`
  content_type :text
  output
end
