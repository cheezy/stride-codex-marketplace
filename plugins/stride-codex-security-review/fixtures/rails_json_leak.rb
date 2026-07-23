# Vulnerable Rails controller: render json: @user leaks sensitive fields.
#
# Trust boundary: the User model carries password_digest, reset_password_token,
# and api_token attributes. render json: @user with no only:/except:/serializer
# emits every column verbatim — including the cryptographic material that
# enables session takeover.
#
# Expected finding: data_exposure (high), CWE-200, A04:2021.

class UsersController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = User.find(params[:id])
    # Vulnerable: ships password_digest, reset_password_token, api_token,
    # two_factor_secret, and encrypted_otp_secret to the client. Any field
    # matching *_token / *_digest / encrypted_* is a session-takeover lever.
    render json: @user
  end

  def index
    @users = User.all
    # Vulnerable: same shape, collection-scale.
    render json: @users
  end

  def me
    # Vulnerable: respond_to-shaped JSON path. Same leak.
    respond_to do |format|
      format.json { render json: current_user }
      format.html { render :show }
    end
  end
end

# The User model implied:
#
# create_table :users do |t|
#   t.string :email, null: false
#   t.string :name
#   t.string :password_digest, null: false        # bcrypt hash
#   t.string :reset_password_token                # password-reset replay token
#   t.string :api_token, null: false              # bearer for the JSON API
#   t.string :two_factor_secret                   # TOTP shared secret
#   t.string :encrypted_otp_secret                # encrypted backup TOTP
#   t.timestamps
# end
