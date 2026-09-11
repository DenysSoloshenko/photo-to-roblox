class OrderReadyNotifier
  def self.call(order, stage:)
    kind = stage == :preview ? "preview_ready" : "order_ready"
    title = stage == :preview ? "Your Roblox preview is ready" : "Your Roblox map is ready to download"
    body = stage == :preview ? "Review the free preview and unlock the editable map for $9 if you love it." : "Your payment is confirmed and the editable Roblox map is ready."

    notification = Notification.create_or_find_by!(order: order, user: order.user, kind: kind) do |record|
      record.title = title
      record.body = body
    end
    OrderMailer.with(order: order, notification: notification, stage: stage.to_s).ready.deliver_now if notification.previously_new_record?
  rescue StandardError => error
    Rails.logger.error("Order notification failed for #{order.public_id}: #{error.class}: #{error.message}")
  end
end
