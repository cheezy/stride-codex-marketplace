# Vulnerable Rails controller: open-redirect via redirect_to params[:url].
#
# Trust boundary: HTTP-supplied `next` and `url` from params flow into
# redirect_to with allow_other_host: true, which intentionally overrides Rails
# 7+ default same-host gating. After login, an attacker substitutes evil.com
# to phish.
#
# Expected finding: input_validation (high), CWE-601, A01:2021.

class SessionsController < ApplicationController
  def create
    user = User.authenticate(params[:email], params[:password])
    if user
      session[:user_id] = user.id
      # Vulnerable: redirect to user-controlled URL with same-host override.
      redirect_to params[:next], allow_other_host: true
    else
      render :new, status: :unauthorized
    end
  end

  def logout_to
    # Vulnerable: redirect_to params[:url] without allow_other_host: false is
    # safe on Rails 7+ by default — but the explicit allow_other_host: true
    # here turns it back on.
    redirect_to params[:url], allow_other_host: true
  end
end
