module Api
  module V1
    module Admin
      class EmailPreviewsController < ApplicationController
        PreviewUser = Data.define(:display_name, :email)
        PreviewAttachment = Data.define(:id, :filename)
        PreviewOrder = Data.define(
          :title, :public_id, :user, :scene_type, :style, :must_preserve, :instructions,
          :rights_confirmed_at, :payment_status, :currency, :price_cents, :delivery_due_at,
          :submitted_at, :source_photos
        )

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
          order = PreviewOrder.new(
            title: "Pacific Centre Lanterns",
            public_id: "demo-order",
            user: user,
            scene_type: "venue",
            style: "faithful",
            must_preserve: "The central red lantern, pink flowers, glass elevator, and circular balconies.",
            instructions: "Keep the space bright and make the walkways playable.",
            rights_confirmed_at: Time.current,
            payment_status: "unpaid",
            currency: "USD",
            price_cents: Order::PRICE_CENTS,
            delivery_due_at: 24.hours.from_now,
            submitted_at: Time.current,
            source_photos: [PreviewAttachment.new(id: 1, filename: "pacific-centre.jpg")]
          )

          case template
          when "password_reset"
            AccountMailer.with(user: user, token: "preview-token").password_reset
          when "preview_ready"
            OrderMailer.with(order: order, stage: "preview").ready
          when "map_ready"
            OrderMailer.with(order: order, stage: "ready").ready
          when "new_order"
            AdminOrderMailer.with(order: order, recipients: [current_user.email]).new_order
          end
        end
      end
    end
  end
end
