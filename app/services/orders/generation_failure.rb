module Orders
  class GenerationFailure
    MAX_ERROR_LENGTH = 1_000

    def initialize(order_id, error)
      @order_id = order_id
      @error = error
    end

    def record
      order = Order.find_by(id: order_id)
      return unless order

      order.with_lock do
        return if order.status.in?(%w[reviewing preview_ready ready delivered])

        order.update!(
          status: "failed",
          generation_finished_at: Time.current,
          generation_error: private_message
        )
      end
      Rails.logger.error({ event: "premium_generation_failed", order_id: order.public_id, error_class: error.class.name }.to_json)
    rescue ActiveRecord::RecordInvalid => invalid
      Rails.logger.error({ event: "premium_generation_failure_record_failed", order_id: order_id, errors: invalid.record.errors.to_hash }.to_json)
    end

    private

    attr_reader :order_id, :error

    def private_message
      "#{error.class.name}: #{error.message}".slice(0, MAX_ERROR_LENGTH)
    end
  end
end
