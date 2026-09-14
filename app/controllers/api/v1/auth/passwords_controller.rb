module Api
  module V1
    module Auth
      class PasswordsController < ApplicationController
        before_action :protect_api!

        def create
          user = User.find_by("lower(email) = ?", params[:email].to_s.strip.downcase)
          if user
            token = user.issue_password_reset!
            AccountMailer.with(user: user, token: token).password_reset.deliver_later
          end

          render json: { ok: true, message: "password_reset_instructions_sent" }, status: :accepted
        end

        def update
          user = User.find_for_password_reset(params[:token])
          return render json: { error: "password_reset_token_invalid" }, status: :unprocessable_entity unless user

          if user.reset_password!(password: params[:password], password_confirmation: params[:password_confirmation])
            sign_in(user)
            render json: { user: user_json(user), csrf_token: csrf_token }
          else
            render json: { errors: user.errors.to_hash }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
