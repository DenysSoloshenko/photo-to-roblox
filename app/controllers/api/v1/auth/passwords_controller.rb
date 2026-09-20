module Api
  module V1
    module Auth
      class PasswordsController < ApplicationController
        before_action :protect_api!

        def create
          user = User.find_by("lower(email) = ?", params[:email].to_s.strip.downcase)
          if user
            token = user.issue_password_reset!
            deliver_password_reset(user, token)
          end

          render json: { ok: true, message: "password_reset_instructions_sent" }, status: :accepted
        end

        def update
          user = User.find_for_password_reset(params[:token])
          return render json: { error: "password_reset_token_invalid" }, status: :unprocessable_entity unless user

          user.with_lock do
            # A concurrent reset may have consumed or replaced this token while
            # this request was waiting for the row lock.
            unless user.password_reset_digest == User.password_reset_digest(params[:token]) &&
                user.password_reset_sent_at && user.password_reset_sent_at >= User::PASSWORD_RESET_TTL.ago
              return render json: { error: "password_reset_token_invalid" }, status: :unprocessable_entity
            end

            if user.reset_password!(password: params[:password], password_confirmation: params[:password_confirmation])
              sign_in(user)
              render json: { user: user_json(user), csrf_token: csrf_token }
            else
              render json: { errors: user.errors.to_hash }, status: :unprocessable_entity
            end
          end
        end

        private

        def deliver_password_reset(user, token)
          # Password reset email is deliberately delivered inside the request.
          # The default in-memory Active Job queue is not durable across Render
          # restarts and can otherwise lose security-critical messages.
          AccountMailer.with(user: user, token: token).password_reset.deliver_now
        rescue StandardError => error
          # Always return the same response for known and unknown addresses.
          # Log only the exception type, never the address or reset token.
          Rails.logger.error("password_reset_delivery_failed error_class=#{error.class}")
        end
      end
    end
  end
end
