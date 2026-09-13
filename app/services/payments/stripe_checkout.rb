module Payments
  class StripeCheckout
    class NotConfigured < StandardError; end
    class InvalidState < StandardError; end

    SavedSession = Struct.new(:id, :url, keyword_init: true)
    REUSE_WINDOW = 23.hours

    def initialize(order)
      @order = order
    end

    def create
      raise NotConfigured, "Add STRIPE_SECRET_KEY to start secure checkout" if ENV["STRIPE_SECRET_KEY"].blank?

      order.with_lock do
        raise InvalidState, "order is not eligible for payment authorization" unless order.can_authorize?
        return saved_session if reusable_checkout?

        attempt = order.checkout_attempts + 1
        session = Stripe::Checkout::Session.create(checkout_params, idempotency_options(attempt))
        order.update!(
          payment_status: "authorization_pending",
          purchase_requested_at: Time.current,
          checkout_started_at: Time.current,
          stripe_checkout_session_id: session.id,
          stripe_checkout_url: session.url,
          checkout_attempts: attempt
        )
        session
      end
    end

    private

    attr_reader :order

    def reusable_checkout?
      order.payment_status == "authorization_pending" && order.stripe_checkout_session_id.present? &&
        order.stripe_checkout_url.present? && order.checkout_started_at.present? && order.checkout_started_at > REUSE_WINDOW.ago
    end

    def saved_session
      SavedSession.new(id: order.stripe_checkout_session_id, url: order.stripe_checkout_url)
    end

    def checkout_params
      {
        mode: "payment",
        client_reference_id: order.public_id,
        customer_email: order.user.email,
        metadata: { order_public_id: order.public_id },
        payment_intent_data: {
          capture_method: "manual",
          receipt_email: order.user.email,
          metadata: { order_public_id: order.public_id }
        },
        line_items: [{
          quantity: 1,
          price_data: {
            currency: order.currency.downcase,
            unit_amount: order.price_cents,
            product_data: { name: "SceneFoundry editable Roblox map", description: order.title }
          }
        }],
        expires_at: 23.hours.from_now.to_i,
        success_url: "#{app_url}/orders?checkout=authorized&order=#{order.public_id}",
        cancel_url: "#{app_url}/orders?checkout=cancelled&order=#{order.public_id}"
      }
    end

    def idempotency_options(attempt)
      { idempotency_key: "order-#{order.public_id}-authorize-#{attempt}" }
    end

    def app_url
      ENV.fetch("APP_URL", "http://127.0.0.1:5173").delete_suffix("/")
    end
  end
end
