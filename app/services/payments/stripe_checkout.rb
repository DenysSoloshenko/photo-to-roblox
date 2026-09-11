module Payments
  class StripeCheckout
    class NotConfigured < StandardError; end

    def initialize(order)
      @order = order
    end

    def create
      raise NotConfigured, "Add STRIPE_SECRET_KEY to start secure checkout" if ENV["STRIPE_SECRET_KEY"].blank?

      session = Stripe::Checkout::Session.create(
        {
          mode: "payment",
          client_reference_id: order.public_id,
          customer_email: order.user.email,
          metadata: { order_public_id: order.public_id },
          payment_intent_data: { metadata: { order_public_id: order.public_id } },
          line_items: [{
            quantity: 1,
            price_data: {
              currency: order.currency.downcase,
              unit_amount: order.price_cents,
              product_data: { name: "SceneFoundry editable Roblox map", description: order.title }
            }
          }],
          success_url: "#{app_url}/orders?checkout=success&order=#{order.public_id}",
          cancel_url: "#{app_url}/orders?checkout=cancelled&order=#{order.public_id}"
        },
        { idempotency_key: "order-#{order.public_id}-#{order.price_cents}" }
      )
      order.update!(
        payment_status: "requested",
        purchase_requested_at: Time.current,
        checkout_started_at: Time.current,
        stripe_checkout_session_id: session.id
      )
      session
    end

    private

    attr_reader :order

    def app_url
      ENV.fetch("APP_URL", "http://127.0.0.1:5173").delete_suffix("/")
    end
  end
end

