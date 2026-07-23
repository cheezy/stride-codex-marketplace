# Smoke-test fixture: Rails/Ruby rule pack — html_safe on user-controlled data
#
# A Rails controller renders a comment field directly with .html_safe,
# disabling ERB's auto-escape. Any HTML in `params[:comment]` reaches the
# rendered page as live markup, including <script> tags. Classic stored XSS.
class CommentsController < ApplicationController
  def show
    @comment = params[:comment]
  end
end

# In app/views/comments/show.html.erb:
#   <%= @comment.html_safe %>
#
# (The fixture's vulnerability is the .html_safe call on params content.)
