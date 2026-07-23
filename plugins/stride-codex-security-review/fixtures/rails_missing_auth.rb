# Vulnerable Rails controller: state-changing actions without
# authentication.
#
# Trust boundary: PostsController inherits from ApplicationController but
# does NOT call before_action :authenticate_user! and does NOT use
# skip_before_action. The destroy action will run for any anonymous
# requester who guesses an id.
#
# Expected finding: authentication (high), CWE-306, A07:2021.

class PostsController < ApplicationController
  # Vulnerable: no before_action :authenticate_user! / :require_login /
  # :authenticate_admin! is set, and the parent ApplicationController
  # (in this fixture's intended context) does not set one either. The
  # destroy / update / create actions run unauth'd.

  def create
    @post = Post.create(post_params)
    redirect_to @post
  end

  def update
    @post = Post.find(params[:id])
    @post.update(post_params)
    redirect_to @post
  end

  def destroy
    @post = Post.find(params[:id])
    @post.destroy
    redirect_to posts_path
  end

  private

  def post_params
    params.require(:post).permit(:title, :body)
  end
end
