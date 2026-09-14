require "cgi"

class AccountMailer < ApplicationMailer
  def password_reset
    @user = params.fetch(:user)
    @reset_url = "#{app_url}/?reset_token=#{CGI.escape(params.fetch(:token))}"
    mail(to: @user.email, subject: "Reset your SceneFoundry password")
  end

  private

  def app_url
    ENV.fetch("APP_URL", "http://127.0.0.1:5173").delete_suffix("/")
  end
end
