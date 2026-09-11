module Api
  module V1
    module Admin
      class OrdersController < ApplicationController
        IMAGE_TYPES = Api::V1::OrdersController::IMAGE_TYPES
        RESULT_EXTENSIONS = %w[.rbxlx].freeze

        before_action :authenticate_user!
        before_action :require_admin!
        before_action :protect_api!, only: :update

        def index
          orders = Order.includes(:user).with_attached_source_photos.with_attached_preview_image.with_attached_result_file
            .order(delivery_due_at: :asc)
          orders = orders.where(status: params[:status]) if Order::STATUSES.include?(params[:status])
          render json: { orders: orders.map { |order| order_json(order) } }
        end

        def show
          render json: { order: order_json(find_order) }
        end

        def update
          order = find_order
          validate_uploads!
          preview_scene_ir = extract_preview(params[:result_file], order.title) if params[:result_file].present?
          Order.transaction do
            order.preview_image.attach(params[:preview_image]) if params[:preview_image].present?
            order.result_file.attach(params[:result_file]) if params[:result_file].present?
            order.preview_scene_ir = preview_scene_ir if preview_scene_ir
            order.update!(update_params)
          end
          render json: { order: order_json(order.reload) }
        rescue ActiveRecord::RecordInvalid => error
          render json: { errors: error.record.errors.to_hash }, status: :unprocessable_entity
        rescue ArgumentError => error
          render json: { errors: [error.message] }, status: :unprocessable_entity
        end

        def download_source
          order = find_order
          attachment = order.source_photos.attachments.find(params[:attachment_id])
          send_data attachment.download,
                    filename: attachment.filename.to_s,
                    type: attachment.content_type,
                    disposition: "attachment"
        end

        private

        def find_order
          Order.find_by!(public_id: params[:public_id])
        end

        def update_params
          params.permit(:status, :admin_notes)
        end

        def validate_uploads!
          preview = params[:preview_image]
          if preview.present?
            raise ArgumentError, "Preview must be JPEG, PNG, or WebP" unless IMAGE_TYPES.include?(preview.content_type)
            raise ArgumentError, "Preview is larger than 10 MB" if preview.size > 10.megabytes
          end

          result = params[:result_file]
          return unless result.present?
          raise ArgumentError, "Result must be an .rbxlx file" unless RESULT_EXTENSIONS.include?(File.extname(result.original_filename).downcase)
          raise ArgumentError, "Result is larger than 50 MB" if result.size > 50.megabytes
        end

        def extract_preview(result, fallback_name)
          xml = result.read
          result.rewind
          Roblox::PreviewExtractor.new.extract(xml, fallback_name: fallback_name)
        end

        def order_json(order)
          OrderSerializer.new(order, admin: true).as_json
        end
      end
    end
  end
end
