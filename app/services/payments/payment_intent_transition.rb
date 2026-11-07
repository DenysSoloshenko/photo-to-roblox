module Payments
  class PaymentIntentTransition
    class InvalidTransition < StandardError; end

    def self.apply!(order, payment_intent, released_status: "cancelled", occurred_at: Time.current)
      new(order, payment_intent, released_status: released_status, occurred_at: occurred_at).apply!
    end

    def initialize(order, payment_intent, released_status:, occurred_at:)
      @order = order
      @payment_intent = payment_intent
      @released_status = released_status
      @occurred_at = occurred_at
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

    attr_reader :order, :payment_intent, :released_status, :occurred_at

    def authorize!
      # Signed events can arrive after capture/refund/release, or while capture
      # is in flight. A stale authorization must never roll that state back.
      return if order.payment_status.in?(%w[capture_pending paid released refund_pending refunded])

      expires_at = authorization_deadline

      order.status = "submitted" if order.status == "payment_pending" || order.retryable_payment_failure?
      order.payment_status = "authorized"
      order.authorized_at ||= occurred_at
      # Card/network windows vary. Never guess six days or extend a recorded
      # hold because an older authorization event was delivered again.
      order.authorization_expires_at = [order.authorization_expires_at, expires_at].compact.min
      order.payment_error = nil
      order.save!
    end

    def authorization_deadline
      charge = Payments::StripeValue.fetch(payment_intent, :latest_charge)
      charge = Stripe::Charge.retrieve(charge) if charge.is_a?(String) && charge.present?
      details = Payments::StripeValue.fetch(charge, :payment_method_details)
      card = Payments::StripeValue.fetch(details, :card)
      timestamp = Payments::StripeValue.fetch(card, :capture_before)
      value = Integer(timestamp.to_s, exception: false)
      unless value && value.positive?
        raise PaymentIntentValidator::InvalidPayment, "Stripe card authorization deadline is missing"
      end

      Time.zone.at(value)
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
      return if order.payment_status.in?(%w[paid refund_pending refunded])

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
      # A declined card can be retried on the same Checkout/PaymentIntent.
      # Late failure events must not roll back an authorization or capture.
      return unless order.payment_status.in?(%w[unpaid authorization_pending failed])
      return unless order.status == "payment_pending" || order.retryable_payment_failure?

      order.update!(status: "payment_pending", payment_status: "authorization_pending", payment_failed_at: Time.current, payment_error: message)
    end
  end
end
