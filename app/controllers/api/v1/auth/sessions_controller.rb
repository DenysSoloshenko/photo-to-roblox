module Api
  module V1
    module Auth
      class SessionsController < ApplicationController
        before_action :protect_api!, only: %i[create destroy]
        before_action :authenticate_user!, only: :destroy

        def show
          authenticate_from_cookie
          render json: {
            user: current_user && user_json(current_user),
            csrf_token: csrf_token,
            oauth_providers: OAuth::Provider.configured_names
          }
        end

        def create
          user = User.find_by("lower(email) = ?", params[:email].to_s.strip.downcase)
          unless user&.password_digest.present? && user.authenticate(params[:password].to_s)
            return render json: { error: "invalid_credentials" }, status: :unauthorized
          end

          sign_in(user)
          render json: { user: user_json(user), csrf_token: csrf_token }
        end

        def destroy
          sign_out
          render json: { ok: true }
        end

        private

        def authenticate_from_cookie
          payload = cookies.encrypted[SESSION_COOKIE]
          user = User.find_by(id: payload&.fetch("user_id", nil))
          @current_user = user if user && payload["session_version"].to_i == user.session_version
        end
      end
    end
  end
end
