module Payments
  class PaymentIntentTransition
    class InvalidTransition < StandardError; end

    def self.apply!(order, payment_intent, released_status: "cancelled")
      new(order, payment_intent, released_status: released_status).apply!
    end

    def initialize(order, payment_intent, released_status:)
      @order = order
      @payment_intent = payment_intent
      @released_status = released_status
    end

    def apply!
      order.with_lock do
        validator = PaymentIntentValidator.new(order, payment_intent)
        validator.validate!
        intent_status = Payments::StripeValue.fetch(payment_intent, :status).to_s
        order.stripe_payment_intent_id ||= validator.payment_intent_id

        case intent_status
        when "requires_capture"
          authorize!
        when "succeeded"
          capture!
        when "canceled"
          release!
        when "requires_payment_method"
          fail_payment!("Stripe could not authorize the payment method")
        else
          raise InvalidTransition, "unsupported PaymentIntent status: #{intent_status}"
        end
      end

      order
    end

    private

    attr_reader :order, :payment_intent, :released_status

    def authorize!
      return if order.payment_status == "authorized" && order.status == "submitted"
      # Signed events can arrive after capture/refund/release, or while capture
      # is in flight. A stale authorization must never roll that state back.
      return if order.payment_status.in?(%w[capture_pending paid released refund_pending refunded])

      order.status = "submitted" if order.status == "payment_pending"
      order.payment_status = "authorized"
      order.authorized_at ||= Time.current
      order.authorization_expires_at ||= 6.days.from_now
      order.payment_error = nil
      order.save!
    end

    def capture!
      return if order.payment_status.in?(%w[paid refund_pending refunded])
      unless order.status == "accepted" && order.payment_status == "capture_pending"
        raise InvalidTransition, "payment was captured without an accepted order"
      end

      order.update!(
        status: "building",
        payment_status: "paid",
        paid_at: Time.current,
        captured_at: Time.current,
        payment_error: nil
      )
    end

    def release!
      return if order.payment_status == "released" && order.status == released_status
      raise InvalidTransition, "captured payment cannot be released" if order.payment_status.in?(%w[paid refund_pending refunded])

      order.update!(
        status: released_status,
        payment_status: "released",
        released_at: Time.current,
        declined_at: (Time.current if released_status == "declined"),
        cancelled_at: (Time.current if released_status == "cancelled"),
        payment_error: nil
      )
    end

    def fail_payment!(message)
      return if order.payment_status.in?(%w[paid released refunded])

      order.update!(status: "failed", payment_status: "failed", payment_failed_at: Time.current, payment_error: message)
    end
  end
end
