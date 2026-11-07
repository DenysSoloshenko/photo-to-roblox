class RecoverPendingWorkJob < ApplicationJob
  queue_as :maintenance

  def perform
    EmailDelivery.where(delivered_at: nil).where("created_at < ?", 5.minutes.ago)
      .where("last_attempt_at IS NULL OR last_attempt_at < ?", 30.minutes.ago).find_each(&:enqueue_delivery)
    return unless ENV["ASTRA_ORDER_AUTOMATION_ENABLED"] == "true"

    Order.where(status: "building", payment_status: "paid", generation_started_at: nil)
      .find_each { |order| GenerateOrderJob.perform_later(order.id) }
  end
end
