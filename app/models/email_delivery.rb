class EmailDelivery < ApplicationRecord
  belongs_to :order
  validates :kind, inclusion: { in: %w[new_order preview_ready order_ready] }
  validates :recipients, presence: true

  after_create_commit :enqueue_delivery

  def enqueue_delivery
    DeliverEmailJob.perform_later(id)
  rescue StandardError => error
    # The durable outbox remains available to RecoverPendingWorkJob.
    Rails.logger.error({ event: "email_enqueue_failed", delivery_id: id, error_class: error.class.name }.to_json)
  end

  def deliver!
    failure = nil
    with_lock do
      return if delivered_at?
      begin
        message.deliver_now
        update!(delivered_at: Time.current, last_error: nil, attempts: attempts + 1, last_attempt_at: Time.current)
      rescue StandardError => error
        update!(last_error: error.class.name, attempts: attempts + 1, last_attempt_at: Time.current)
        failure = error
      end
    end
    raise failure if failure
  end

  private

  def message
    if kind == "new_order"
      AdminOrderMailer.with(order: order, recipients: recipients, delivery_id: id).new_order
    else
      OrderMailer.with(order: order, recipients: recipients, delivery_id: id,
        stage: kind == "preview_ready" ? "preview" : "download").ready
    end
  end
end
