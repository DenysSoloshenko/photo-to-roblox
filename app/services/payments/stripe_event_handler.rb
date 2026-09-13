module Payments
  class StripeEventHandler
    class InvalidEvent < StandardError; end

    EVENT_TYPES = %w[
      checkout.session.completed
      checkout.session.async_payment_succeeded
      checkout.session.expired
      payment_intent.amount_capturable_updated
      payment_intent.succeeded
      payment_intent.payment_failed
      payment_intent.canceled
      charge.refunded
    ].freeze

    def self.call(event)
      new(event).call
    end

    def initialize(event)
      @event = event
      @event_id = Payments::StripeValue.fetch(event, :id).to_s
      @event_type = Payments::StripeValue.fetch(event, :type).to_s
      @object = Payments::StripeValue.fetch(Payments::StripeValue.fetch(event, :data), :object)
    end

    def call
      raise InvalidEvent, "Stripe event id is missing" if event_id.blank?
      raise InvalidEvent, "Stripe event type is missing" if event_type.blank?

      StripeEvent.transaction do
        StripeEvent.create!(
          event_id: event_id,
          event_type: event_type,
          order_public_id: inferred_public_id,
          stripe_created_at: stripe_created_at,
          processed_at: Time.current
        )
        dispatch if EVENT_TYPES.include?(event_type)
      end
      :processed
    rescue ActiveRecord::RecordNotUnique => error
      return :duplicate if StripeEvent.exists?(event_id: event_id)

      raise error
    rescue ActiveRecord::RecordInvalid => error
      return :duplicate if StripeEvent.exists?(event_id: event_id)

      raise InvalidEvent, "Stripe event transition was rejected: #{error.record.errors.full_messages.join(', ')}"
    end

    private

    attr_reader :event, :event_id, :event_type, :object

    def dispatch
      case event_type
      when "checkout.session.completed", "checkout.session.async_payment_succeeded"
        handle_checkout_completed
      when "checkout.session.expired"
        handle_checkout_expired
      when "payment_intent.amount_capturable_updated", "payment_intent.succeeded", "payment_intent.payment_failed", "payment_intent.canceled"
        handle_payment_intent
      when "charge.refunded"
        handle_charge_refunded
      end
    end

    def handle_checkout_completed
      order = order_from_public_id!
      validate_checkout!(order)
      payment_intent = Payments::StripeValue.fetch(object, :payment_intent)
      intent_id = Payments::StripeValue.fetch(payment_intent, :id).presence || payment_intent.to_s.presence
      raise InvalidEvent, "checkout has no payment intent" if intent_id.blank?

      order.with_lock do
        if order.stripe_payment_intent_id.present? && order.stripe_payment_intent_id != intent_id
          raise InvalidEvent, "checkout payment intent does not match order"
        end
        return if order.payment_status.in?(%w[authorized capture_pending paid])

        order.update!(stripe_payment_intent_id: intent_id, payment_status: "authorization_pending", payment_error: nil)
      end
    end

    def handle_checkout_expired
      order = order_from_public_id!
      validate_checkout!(order)
      order.with_lock do
        return unless order.status == "payment_pending" && order.payment_status == "authorization_pending"

        order.update!(
          payment_status: "unpaid",
          stripe_checkout_session_id: nil,
          stripe_checkout_url: nil,
          checkout_started_at: nil
        )
      end
    end

    def handle_payment_intent
      order = order_from_payment_intent!
      released_status = order.status == "declined" ? "declined" : "cancelled"
      Payments::PaymentIntentTransition.apply!(order, object, released_status: released_status)
    rescue Payments::PaymentIntentTransition::InvalidTransition, Payments::PaymentIntentValidator::InvalidPayment => error
      raise InvalidEvent, error.message
    end

    def handle_charge_refunded
      payment_intent_id = Payments::StripeValue.fetch(object, :payment_intent).to_s
      order = Order.find_by(stripe_payment_intent_id: payment_intent_id)
      raise InvalidEvent, "refunded charge does not match an order" unless order

      currency = Payments::StripeValue.fetch(object, :currency).to_s
      amount = Payments::StripeValue.fetch(object, :amount_refunded).to_i
      raise InvalidEvent, "refund currency does not match order" unless currency.casecmp?(order.currency)
      raise InvalidEvent, "refund amount does not match order" unless amount == order.price_cents

      order.with_lock do
        return if order.payment_status == "refunded"
        raise InvalidEvent, "uncaptured order cannot be refunded" unless order.payment_status.in?(%w[paid refund_pending])

        order.update!(payment_status: "refunded", refunded_at: Time.current, payment_error: nil)
      end
    end

    def order_from_public_id!
      order = Order.find_by(public_id: inferred_public_id)
      raise InvalidEvent, "Stripe event order does not exist" unless order

      order
    end

    def order_from_payment_intent!
      public_id = Payments::StripeValue.metadata_value(object, :order_public_id).presence
      order = Order.find_by(public_id: public_id) if public_id
      intent_id = Payments::StripeValue.fetch(object, :id).to_s
      order ||= Order.find_by(stripe_payment_intent_id: intent_id)
      raise InvalidEvent, "payment intent does not match an order" unless order

      order
    end

    def validate_checkout!(order)
      session_id = Payments::StripeValue.fetch(object, :id).to_s
      raise InvalidEvent, "checkout session does not match order" unless session_id == order.stripe_checkout_session_id
      raise InvalidEvent, "checkout amount does not match order" unless Payments::StripeValue.fetch(object, :amount_total).to_i == order.price_cents
      unless Payments::StripeValue.fetch(object, :currency).to_s.casecmp?(order.currency)
        raise InvalidEvent, "checkout currency does not match order"
      end

      details = Payments::StripeValue.fetch(object, :customer_details)
      email = Payments::StripeValue.fetch(details, :email).presence || Payments::StripeValue.fetch(object, :customer_email).presence
      raise InvalidEvent, "checkout customer does not match order" if email && !email.casecmp?(order.user.email)
    end

    def inferred_public_id
      Payments::StripeValue.metadata_value(object, :order_public_id).presence ||
        Payments::StripeValue.fetch(object, :client_reference_id).presence
    end

    def stripe_created_at
      value = Payments::StripeValue.fetch(event, :created)
      Time.zone.at(value.to_i) if value.present?
    end
  end
end
