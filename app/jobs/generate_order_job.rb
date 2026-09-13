class GenerateOrderJob < ApplicationJob
  queue_as :premium_generation

  discard_on ActiveJob::DeserializationError

  def perform(order_id)
    order = Order.find(order_id)
    reservation = Orders::GenerationGate.new(order).reserve!
    return unless reservation

    Orders::PremiumGenerator.new(order).call
  rescue StandardError => error
    Orders::GenerationFailure.new(order_id, error).record
  end
end
