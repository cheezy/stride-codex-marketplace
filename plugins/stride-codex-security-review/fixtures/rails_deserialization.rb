# Vulnerable Rails controller: unsafe deserialization of HTTP-supplied data.
#
# Trust boundary: request body / params flow into Marshal.load, YAML.load
# without permitted_classes, and YAML.unsafe_load. All three are remote-code-
# execution sinks (Rails has shipped multiple CVEs in this lineage:
# CVE-2013-0156, CVE-2022-32224).
#
# Expected finding: xss_or_code_exec (critical), CWE-502, A08:2021.

require "yaml"

class ImportsController < ApplicationController
  def restore
    # Vulnerable: Marshal.load on attacker-controlled bytes -> arbitrary
    # _marshal_dump payload -> RCE.
    snapshot = Base64.decode64(params[:snapshot])
    state = Marshal.load(snapshot)
    render plain: "Restored: #{state.inspect}"
  end

  def parse_config
    # Vulnerable: YAML.load without permitted_classes will accept !ruby/object
    # tags and instantiate arbitrary classes at parse time. Pre-7.0 Rails the
    # default permitted_classes was [], so this was already restricted; on 7.0+
    # the default is the same — but YAML.unsafe_load explicitly bypasses it.
    cfg = YAML.load(request.body.read)
    render plain: "Loaded: #{cfg.keys.length} keys"
  end

  def parse_unsafe
    # Vulnerable: YAML.unsafe_load explicitly opts out of the permitted_classes
    # allow-list — even on Rails 7+ with safe defaults.
    cfg = YAML.unsafe_load(params[:yaml])
    render plain: "Unsafe-loaded"
  end
end
