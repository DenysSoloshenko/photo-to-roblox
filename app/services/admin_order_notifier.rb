class AdminOrderNotifier
  def self.call(order)
    recipients = ENV.fetch("ADMIN_EMAILS", "").split(",").map(&:strip).reject(&:blank?).uniq
    return if recipients.empty?

    AdminOrderMailer.with(order: order, recipients: recipients).new_order.deliver_now
  rescue StandardError => error
    Rails.logger.error("Admin order notification failed for #{order.public_id}: #{error.class}: #{error.message}")
  end
end
