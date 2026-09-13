module Payments
  class OrderActions
    class InvalidState < StandardError; end
    class NotConfigured < StandardError; end

    def initialize(order)
      @order = order
    end

    def accept!
      require_stripe!
      order.with_lock do
        if order.can_accept?
          order.update!(
            status: "accepted",
            payment_status: "capture_pending",
            accepted_at: Time.current,
            capture_requested_at: Time.current,
            payment_error: nil
          )
        elsif !(order.status == "accepted" && order.payment_status == "capture_pending")
          raise InvalidState, "order must have a current card authorization"
        end
      end
      intent = Stripe::PaymentIntent.capture(order.stripe_payment_intent_id, {}, { idempotency_key: "order-#{order.public_id}-capture" })
      Payments::PaymentIntentTransition.apply!(order, intent)
    rescue Stripe::StripeError => error
      record_payment_failure(error)
      raise
    end

    def decline!
      require_stripe!
      order.with_lock do
        if order.can_decline?
          order.update!(status: "declined", declined_at: Time.current, payment_error: nil)
        elsif !(order.status == "declined" && order.payment_status == "authorized")
          raise InvalidState, "only an authorized submitted order can be declined"
        end
      end
      intent = Stripe::PaymentIntent.cancel(order.stripe_payment_intent_id, {}, { idempotency_key: "order-#{order.public_id}-decline" })
      Payments::PaymentIntentTransition.apply!(order, intent, released_status: "declined")
    rescue Stripe::StripeError => error
      record_payment_failure(error)
      raise
    end

    def cancel!
      order.with_lock do
        raise InvalidState, "order can no longer be cancelled" unless order.can_cancel?
      end

      if order.stripe_payment_intent_id.present?
        require_stripe!
        intent = Stripe::PaymentIntent.cancel(order.stripe_payment_intent_id, {}, { idempotency_key: "order-#{order.public_id}-cancel" })
        Payments::PaymentIntentTransition.apply!(order, intent, released_status: "cancelled")
      else
        expire_checkout_if_needed!
        order.with_lock do
          order.update!(status: "cancelled", payment_status: "released", released_at: Time.current, cancelled_at: Time.current)
        end
      end
      order
    rescue Stripe::StripeError => error
      record_payment_failure(error)
      raise
    end

    private

    attr_reader :order

    def require_stripe!
      raise NotConfigured, "STRIPE_SECRET_KEY is not configured" if ENV["STRIPE_SECRET_KEY"].blank?
    end

    def expire_checkout_if_needed!
      return if order.stripe_checkout_session_id.blank?

      require_stripe!
      Stripe::Checkout::Session.expire(
        order.stripe_checkout_session_id,
        {},
        { idempotency_key: "order-#{order.public_id}-expire-checkout" }
      )
    end

    def record_payment_failure(error)
      order.with_lock do
        return if order.payment_status == "paid"

        order.update!(
          payment_failed_at: Time.current,
          payment_error: "#{error.class.name}: #{error.message}".slice(0, 1_000)
        )
      end
    rescue ActiveRecord::RecordInvalid
      nil
    end
  end
end
