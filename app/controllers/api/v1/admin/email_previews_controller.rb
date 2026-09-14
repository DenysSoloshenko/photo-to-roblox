module Api
  module V1
    module Admin
      class EmailPreviewsController < ApplicationController
        PreviewUser = Data.define(:display_name, :email)
        PreviewOrder = Data.define(:title, :public_id, :user)

        before_action :authenticate_user!
        before_action :require_admin!

        def show
          mail = build_mail(params[:template])
          return head :not_found unless mail

          response.headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; img-src data:"
          render html: mail.html_part.body.decoded.html_safe, layout: false
        end

        private

        def build_mail(template)
          user = PreviewUser.new(display_name: "Alex", email: current_user.email)
          order = PreviewOrder.new(title: "Pacific Centre Lanterns", public_id: "demo-order", user: user)

          case template
          when "password_reset"
            AccountMailer.with(user: user, token: "preview-token").password_reset
          when "preview_ready"
            OrderMailer.with(order: order, stage: "preview").ready
          when "map_ready"
            OrderMailer.with(order: order, stage: "ready").ready
          end
        end
      end
    end
  end
end
