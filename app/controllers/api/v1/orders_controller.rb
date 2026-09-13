module Api
  module V1
    class OrdersController < ApplicationController
      IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze
      MAX_IMAGE_SIZE = 10.megabytes

      before_action :authenticate_user!
      before_action :protect_api!, only: %i[create authorize_payment purchase cancel]

      def index
        orders = current_user.orders.with_attached_source_photos.with_attached_preview_image.with_attached_result_file.order(created_at: :desc)
        render json: { orders: orders.map { |order| order_json(order) } }
      end

      def show
        render json: { order: order_json(find_order) }
      end

      def create
        photos = Array(params[:source_photos]).compact
        errors = validate_images(photos)
        errors << "Confirm that you may use the uploaded photos" unless ActiveModel::Type::Boolean.new.cast(params[:rights_confirmed])
        return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

        order = current_user.orders.new(order_params.merge(
          status: "payment_pending",
          payment_status: "unpaid",
          price_cents: Order::PRICE_CENTS,
          currency: "USD",
          rights_confirmed_at: Time.current
        ))
        Order.transaction do
          order.save!
          order.source_photos.attach(photos)
        end
        render json: { order: order_json(order) }, status: :created
      rescue ActiveRecord::RecordInvalid => error
        render json: { errors: error.record.errors.to_hash }, status: :unprocessable_entity
      end

      def download
        order = find_order
        attachment = case params[:kind]
                     when "result" then order.result_file if order.ready_for_download?
                     when "preview" then order.preview_image if order.status.in?(%w[preview_ready ready delivered])
                     end
        return render json: { error: "file_not_available" }, status: :not_found unless attachment&.attached?

        send_data attachment.download,
                  filename: attachment.filename.to_s,
                  type: attachment.content_type,
                  disposition: params[:kind] == "preview" ? "inline" : "attachment"
      end

      def authorize_payment
        order = find_order
        checkout = ::Payments::StripeCheckout.new(order).create
        render json: { order: order_json(order.reload), checkout_url: checkout.url }
      rescue ::Payments::StripeCheckout::NotConfigured => error
        render json: { error: "stripe_not_configured", message: error.message }, status: :service_unavailable
      rescue ::Payments::StripeCheckout::InvalidState => error
        render json: { error: "payment_authorization_not_allowed", message: error.message }, status: :unprocessable_entity
      rescue Stripe::StripeError => error
        Rails.logger.warn({ event: "stripe_checkout_failed", order_id: order&.public_id, error_class: error.class.name }.to_json)
        render json: { error: "payment_service_unavailable" }, status: :bad_gateway
      end

      def purchase
        authorize_payment
      end

      def cancel
        order = find_order
        ::Payments::OrderActions.new(order).cancel!
        render json: { order: order_json(order.reload) }
      rescue ::Payments::OrderActions::InvalidState => error
        render json: { error: "order_cancellation_not_allowed", message: error.message }, status: :unprocessable_entity
      rescue ::Payments::OrderActions::NotConfigured
        render json: { error: "stripe_not_configured" }, status: :service_unavailable
      rescue Stripe::StripeError
        render json: { error: "payment_service_unavailable" }, status: :bad_gateway
      end

      private

      def find_order
        current_user.orders.find_by!(public_id: params[:public_id])
      end

      def order_params
        params.permit(:title, :scene_type, :style, :must_preserve, :instructions)
      end

      def validate_images(photos)
        errors = []
        errors << "Upload between 1 and 3 source photos" unless photos.size.between?(1, 3)
        photos.each do |photo|
          errors << "#{photo.original_filename} must be JPEG, PNG, or WebP" unless IMAGE_TYPES.include?(photo.content_type)
          errors << "#{photo.original_filename} is larger than 10 MB" if photo.size > MAX_IMAGE_SIZE
        end
        errors
      end

      def order_json(order)
        OrderSerializer.new(order).as_json
      end
    end
  end
end
