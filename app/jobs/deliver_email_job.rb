class DeliverEmailJob < ApplicationJob
  queue_as :mailers
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(delivery_id)
    EmailDelivery.find(delivery_id).deliver!
  end
end
