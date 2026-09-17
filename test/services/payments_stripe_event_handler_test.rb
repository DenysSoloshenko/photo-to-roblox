require "test_helper"
require "ostruct"

class PaymentsStripeEventHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = User.create!(email: "buyer@example.com", display_name: "Buyer", password: "secure-password")
    @order = @user.orders.create!(title: "Paid garden", rights_confirmed_at: Time.current)
    @order.update!(
      payment_status: "authorization_pending",
      stripe_checkout_session_id: "cs_test_authorize",
      stripe_checkout_url: "https://checkout.stripe.test/session",
      checkout_started_at: Time.current
    )
  end

  test "deduplicates events and authorizes only matching amount currency identity and customer" do
    completed = stripe_event("evt_checkout", "checkout.session.completed", OpenStruct.new(
      id: "cs_test_authorize",
      metadata: { "order_public_id" => @order.public_id },
      client_reference_id: @order.public_id,
      amount_total: 1_900,
      currency: "usd",
      customer_details: OpenStruct.new(email: @user.email),
      payment_intent: "pi_test_authorize"
    ))
    assert_equal :processed, Payments::StripeEventHandler.call(completed)

    capturable = stripe_event("evt_capturable", "payment_intent.amount_capturable_updated", payment_intent(
      id: "pi_test_authorize", status: "requires_capture"
    ))
    assert_equal :processed, Payments::StripeEventHandler.call(capturable)
    assert_equal :duplicate, Payments::StripeEventHandler.call(capturable)

    @order.reload
    assert_equal "submitted", @order.status
    assert_equal "authorized", @order.payment_status
    assert @order.authorized_at.present?
    assert_equal 2, StripeEvent.count
  end

  test "rejects an amount mismatch without recording the event" do
    event = stripe_event("evt_bad_amount", "payment_intent.amount_capturable_updated", payment_intent(
      id: "pi_bad", status: "requires_capture", amount: 2_000
    ))

    assert_raises(Payments::StripeEventHandler::InvalidEvent) { Payments::StripeEventHandler.call(event) }
    refute StripeEvent.exists?(event_id: "evt_bad_amount")
    assert_equal "authorization_pending", @order.reload.payment_status
  end

  test "verified capture starts manual work without AI and a full refund revokes download" do
    @order.update!(
      status: "submitted",
      payment_status: "authorized",
      stripe_payment_intent_id: "pi_paid",
      authorized_at: Time.current,
      authorization_expires_at: 5.days.from_now
    )
    @order.update!(status: "accepted", payment_status: "capture_pending", capture_requested_at: Time.current)

    assert_no_enqueued_jobs only: GenerateOrderJob do
      Payments::StripeEventHandler.call(stripe_event(
        "evt_paid", "payment_intent.succeeded", payment_intent(id: "pi_paid", status: "succeeded")
      ))
    end
    assert_equal "building", @order.reload.status
    assert_equal "paid", @order.payment_status

    Payments::StripeEventHandler.call(stripe_event("evt_refund", "charge.refunded", OpenStruct.new(
      payment_intent: "pi_paid", currency: "usd", amount_refunded: 1_900
    )))
    assert_equal "refunded", @order.reload.payment_status
    refute @order.ready_for_download?
  end

  test "late authorization and capture events preserve fulfillment and refund state" do
    @order.update!(status: "submitted", payment_status: "authorized", stripe_payment_intent_id: "pi_late")
    @order.update!(status: "accepted", payment_status: "capture_pending")
    Payments::StripeEventHandler.call(stripe_event("evt_late_capture", "payment_intent.succeeded", payment_intent(id: "pi_late", status: "succeeded")))
    @order.reload.update!(status: "reviewing")
    Payments::StripeEventHandler.call(stripe_event("evt_late_authorize", "payment_intent.amount_capturable_updated", payment_intent(id: "pi_late", status: "requires_capture")))
    Payments::StripeEventHandler.call(stripe_event("evt_late_capture_2", "payment_intent.succeeded", payment_intent(id: "pi_late", status: "succeeded")))
    assert_equal "reviewing", @order.reload.status
    assert_equal "paid", @order.payment_status
    @order.update!(payment_status: "refunded")
    Payments::StripeEventHandler.call(stripe_event("evt_after_refund", "payment_intent.succeeded", payment_intent(id: "pi_late", status: "succeeded")))
    assert_equal "refunded", @order.reload.payment_status
  end

  test "validates against the locked current payment intent rather than a stale order" do
    stale_order = Order.find(@order.id)
    @order.update!(stripe_payment_intent_id: "pi_current")
    assert_raises(Payments::PaymentIntentValidator::InvalidPayment) do
      Payments::PaymentIntentTransition.apply!(stale_order, payment_intent(id: "pi_stale", status: "requires_capture"))
    end
    assert_equal "authorization_pending", @order.reload.payment_status
  end

  private

  def payment_intent(id:, status:, amount: 1_900)
    OpenStruct.new(
      id: id,
      status: status,
      amount: amount,
      currency: "usd",
      metadata: { "order_public_id" => @order.public_id },
      receipt_email: @user.email
    )
  end

  def stripe_event(id, type, object)
    OpenStruct.new(id: id, type: type, created: Time.current.to_i, data: OpenStruct.new(object: object))
  end
end
