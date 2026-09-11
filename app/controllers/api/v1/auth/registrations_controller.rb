module Api
  module V1
    module Auth
      class RegistrationsController < ApplicationController
        before_action :protect_api!

        def create
          unless ActiveModel::Type::Boolean.new.cast(params[:terms_accepted])
            return render json: { errors: { terms_accepted: ["must be accepted"] } }, status: :unprocessable_entity
          end

          user = User.new(
            email: params[:email],
            display_name: params[:display_name],
            password: params[:password],
            password_confirmation: params[:password_confirmation],
            terms_accepted_at: Time.current
          )
          user.errors.add(:password, "is required") if params[:password].blank?

          if user.errors.empty? && user.save
            sign_in(user)
            render json: { user: user_json(user), csrf_token: csrf_token }, status: :created
          else
            render json: { errors: user.errors.to_hash }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
