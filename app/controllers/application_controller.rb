class ApplicationController < ActionController::API
  include ActionController::Cookies

  SESSION_COOKIE = :scene_foundry_session
  CSRF_COOKIE = :scene_foundry_csrf
  SESSION_TTL = 30.days

  attr_reader :current_user

  before_action :prevent_private_response_caching

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end

  private

  def prevent_private_response_caching
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
  end

  def authenticate_user!
    payload = cookies.encrypted[SESSION_COOKIE]
    @current_user = User.find_by(id: payload&.fetch("user_id", nil))
    valid = @current_user && payload["session_version"].to_i == @current_user.session_version
    return if valid

    clear_session_cookie
    render json: { error: "authentication_required" }, status: :unauthorized
  end

  def require_admin!
    return if current_user&.admin?

    render json: { error: "admin_required" }, status: :forbidden
  end

  def protect_api!
    expected = cookies.encrypted[CSRF_COOKIE]
    supplied = request.headers["X-CSRF-Token"].to_s
    valid = expected.present? && supplied.present? && expected.bytesize == supplied.bytesize &&
      ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
    render json: { error: "invalid_csrf_token" }, status: :unprocessable_entity unless valid
  end

  def csrf_token
    cookies.encrypted[CSRF_COOKIE].presence || rotate_csrf_token
  end

  def rotate_csrf_token
    token = SecureRandom.urlsafe_base64(32)
    cookies.encrypted[CSRF_COOKIE] = cookie_options.merge(value: token, expires: SESSION_TTL.from_now)
    token
  end

  def sign_in(user)
    cookies.encrypted[SESSION_COOKIE] = cookie_options.merge(
      value: { user_id: user.id, session_version: user.session_version },
      expires: SESSION_TTL.from_now
    )
    @current_user = user
    rotate_csrf_token
  end

  def sign_out
    clear_session_cookie
    cookies.delete(CSRF_COOKIE, cookie_delete_options)
    @current_user = nil
  end

  def clear_session_cookie
    cookies.delete(SESSION_COOKIE, cookie_delete_options)
  end

  def cookie_options
    { httponly: true, same_site: :lax, secure: Rails.env.production? }
  end

  def cookie_delete_options
    { httponly: true, same_site: :lax, secure: Rails.env.production? }
  end

  def user_json(user)
    {
      id: user.id,
      email: user.email,
      display_name: user.display_name,
      admin: user.admin?,
      oauth_only: user.oauth_only?
    }
  end
end
