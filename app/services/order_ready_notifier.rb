class OrderReadyNotifier
  def self.call(order, stage:)
    kind = stage == :preview ? "preview_ready" : "order_ready"
    title = stage == :preview ? "Your Roblox preview is ready" : "Your Roblox map is ready to download"
    body = stage == :preview ? "Your approved interactive preview is ready. We will notify you when the editable map is released." : "Your payment is confirmed and the editable Roblox map is ready."

    Notification.find_or_create_by!(order: order, user: order.user, kind: kind) do |record|
      record.title = title
      record.body = body
    end
    EmailDelivery.create_or_find_by!(order: order, kind: kind) { |delivery| delivery.recipients = [order.user.email] }
  end
end
