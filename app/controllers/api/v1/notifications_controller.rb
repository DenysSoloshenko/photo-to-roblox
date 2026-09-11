module Api
  module V1
    class NotificationsController < ApplicationController
      before_action :authenticate_user!
      before_action :protect_api!, only: :read

      def index
        notifications = current_user.notifications.order(created_at: :desc).limit(50)
        render json: { notifications: notifications.map { |notification| notification_json(notification) } }
      end

      def read
        notification = current_user.notifications.find(params[:id])
        notification.update!(read_at: Time.current)
        render json: { notification: notification_json(notification) }
      end

      private

      def notification_json(notification)
        {
          id: notification.id,
          order_public_id: notification.order.public_id,
          kind: notification.kind,
          title: notification.title,
          body: notification.body,
          read: notification.read?,
          created_at: notification.created_at.iso8601
        }
      end
    end
  end
end
