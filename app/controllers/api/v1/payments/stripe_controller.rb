module Api
  module V1
    module Payments
      class StripeController < ApplicationController
        def webhook
          secret = ENV["STRIPE_WEBHOOK_SECRET"]
          return render json: { error: "stripe_webhook_not_configured" }, status: :service_unavailable if secret.blank?

          event = Stripe::Webhook.construct_event(request.raw_post, request.headers["Stripe-Signature"], secret)
          ::Payments::StripeEventHandler.call(event)
          head :ok
        rescue JSON::ParserError, Stripe::SignatureVerificationError
          render json: { error: "invalid_stripe_webhook" }, status: :bad_request
        rescue ::Payments::StripeEventHandler::InvalidEvent, ::Payments::PaymentIntentValidator::InvalidPayment => error
          Rails.logger.warn({ event: "stripe_webhook_rejected", message: error.message }.to_json)
          render json: { error: "stripe_event_rejected" }, status: :unprocessable_entity
        end
      end
    end
  end
end
