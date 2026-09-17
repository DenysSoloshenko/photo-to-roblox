module Payments
  class PaymentIntentValidator
    class InvalidPayment < StandardError; end

    def initialize(order, payment_intent)
      @order = order
      @payment_intent = payment_intent
    end

    def validate!
      raise InvalidPayment, "payment intent id is missing" if payment_intent_id.blank?
      require_match!("payment intent", payment_intent_id, order.stripe_payment_intent_id) if order.stripe_payment_intent_id.present?
      require_match!("order", Payments::StripeValue.metadata_value(payment_intent, :order_public_id), order.public_id)
      require_match!("amount", Payments::StripeValue.fetch(payment_intent, :amount).to_i, order.price_cents)
      require_match!("currency", Payments::StripeValue.fetch(payment_intent, :currency).to_s.downcase, order.currency.downcase)
      email = Payments::StripeValue.fetch(payment_intent, :receipt_email).presence
      require_match!("customer email", email.downcase, order.user.email.downcase) if email
      true
    end

    def payment_intent_id
      Payments::StripeValue.fetch(payment_intent, :id).to_s
    end

    private

    attr_reader :order, :payment_intent

    def require_match!(field, actual, expected)
      return if actual == expected

      raise InvalidPayment, "#{field} does not match order"
    end
  end
end
