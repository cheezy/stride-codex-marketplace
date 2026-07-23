# Vulnerable Rails query: ActiveRecord::Base.connection.execute with
# string interpolation from params.
#
# Trust boundary: params[:status] flows into the SQL string via #{}
# interpolation, bypassing the parameterized-query default. A different
# sink from find_by_sql but the same shape and impact.
#
# Expected finding: injection (critical), CWE-89, A03:2021.

class ReportsController < ApplicationController
  def index
    # Vulnerable: status from params is interpolated into the SQL string.
    # Attack: ?status=open' OR 1=1 --
    status = params[:status]
    sql = "SELECT id, title, status FROM tasks WHERE status = '#{status}'"
    @rows = ActiveRecord::Base.connection.execute(sql)
    render :index
  end

  def by_user
    # Vulnerable: same shape via .exec_query with user-controlled id.
    user_id = params[:user_id]
    @rows = ActiveRecord::Base.connection.exec_query(
      "SELECT * FROM tasks WHERE user_id = #{user_id}"
    )
    render :index
  end
end
