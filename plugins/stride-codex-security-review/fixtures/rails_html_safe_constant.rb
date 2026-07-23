# Negative-control fixture for the Rails html_safe XSS rule.
#
# This is the SAFE shape: .html_safe applied to string literals known at
# compile time, never to params or user-controlled input. The Rails html_safe
# rule in agents/security-reviewer.md MUST NOT fire on this file.
#
# Expected: zero findings on this file (EXPECTED.md asserts → NONE).

class ApplicationHelper
  # Safe: the wrapped string is a compile-time constant.
  ICON_HTML = "<i class='icon-check'></i>".html_safe

  # Safe: argument is a controlled symbol mapped to a fixed lookup table.
  STATUS_BADGES = {
    open:     "<span class='badge badge-open'>Open</span>".html_safe,
    closed:   "<span class='badge badge-closed'>Closed</span>".html_safe,
    pending:  "<span class='badge badge-pending'>Pending</span>".html_safe
  }.freeze

  def status_badge(status_key)
    # Safe: status_key is validated against an explicit allow-list before lookup.
    return "".html_safe unless STATUS_BADGES.key?(status_key)
    STATUS_BADGES[status_key]
  end

  # Safe: tag content comes from Rails' content_tag helper which escapes its
  # own input; .html_safe on the WRAPPED output is fine because the wrap is a
  # known-good HTML structure with the escaped content inside.
  def wrapped_message(message)
    content_tag(:div, message, class: "alert alert-info")
  end
end
