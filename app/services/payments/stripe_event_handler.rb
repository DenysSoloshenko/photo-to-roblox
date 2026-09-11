module Payments
  class StripeEventHandler
    COMPLETED_EVENTS = %w[checkout.session.completed checkout.session.async_payment_succeeded].freeze

    def self.call(event)
      return unless COMPLETED_EVENTS.include?(event.type)

      session = event.data.object
      public_id = session.metadata&.[]("order_public_id").presence || session.client_reference_id
      order = Order.find_by(public_id: public_id)
      return unless order
      return unless order.stripe_checkout_session_id == session.id
      return unless session.payment_status == "paid"
      return unless session.currency.to_s.casecmp?(order.currency)
      return unless session.amount_total.to_i == order.price_cents

      order.with_lock do
        next if order.payment_status == "paid"

        order.payment_status = "paid"
        order.stripe_payment_intent_id = session.payment_intent
        order.paid_at = Time.current
        order.status = "ready" if order.status == "preview_ready"
        order.save!
      end
    end
  end
end
