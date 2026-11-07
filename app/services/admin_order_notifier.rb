class AdminOrderNotifier
  def self.call(order)
    recipients = ENV.fetch("ADMIN_EMAILS", "").split(",").map(&:strip).reject(&:blank?).uniq
    return if recipients.empty?

    EmailDelivery.create_or_find_by!(order: order, kind: "new_order") { |delivery| delivery.recipients = recipients }
  end
end
