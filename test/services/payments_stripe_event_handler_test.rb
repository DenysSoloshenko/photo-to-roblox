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

  test "a declined card can be retried in the same checkout" do
    Payments::StripeEventHandler.call(stripe_event("evt_declined_card", "payment_intent.payment_failed",
      payment_intent(id: "pi_retry", status: "requires_payment_method")))
    assert @order.reload.can_authorize?
    assert @order.can_cancel?

    Payments::StripeEventHandler.call(stripe_event("evt_retry_authorized", "payment_intent.amount_capturable_updated",
      payment_intent(id: "pi_retry", status: "requires_capture")))
    assert_equal "submitted", @order.reload.status
    assert @order.can_accept?
  end

  test "delivery clock starts at successful authorization and is not extended by a replay" do
    assert_nil @order.delivery_due_at
    travel 3.days do
      Payments::StripeEventHandler.call(stripe_event("evt_clock", "payment_intent.amount_capturable_updated",
        payment_intent(id: "pi_clock", status: "requires_capture")))
      assert_equal Time.current + 24.hours, @order.reload.delivery_due_at
    end
    due = @order.delivery_due_at
    Payments::StripeEventHandler.call(stripe_event("evt_clock_replay", "payment_intent.amount_capturable_updated",
      payment_intent(id: "pi_clock", status: "requires_capture")))
    assert_equal due, @order.reload.delivery_due_at
  end

  test "a full refund before the capture webhook is terminal" do
    @order.update!(status: "submitted", payment_status: "authorized", stripe_payment_intent_id: "pi_refund_first")
    @order.update!(status: "accepted", payment_status: "capture_pending", capture_requested_at: Time.current)
    Payments::StripeEventHandler.call(stripe_event("evt_refund_first", "charge.refunded", OpenStruct.new(
      payment_intent: "pi_refund_first", currency: "usd", amount: 1_900, amount_refunded: 1_900, captured: true
    )))
    Payments::StripeEventHandler.call(stripe_event("evt_capture_after_refund", "payment_intent.succeeded",
      payment_intent(id: "pi_refund_first", status: "succeeded")))
    assert_equal "refunded", @order.reload.payment_status
    refute @order.can_accept?
    refute @order.can_download?
  end

  test "a stale card failure cannot overwrite a successful authorization" do
    Payments::StripeEventHandler.call(stripe_event("evt_good_card", "payment_intent.amount_capturable_updated",
      payment_intent(id: "pi_stale_failure", status: "requires_capture")))
    Payments::StripeEventHandler.call(stripe_event("evt_bad_card_late", "payment_intent.payment_failed",
      payment_intent(id: "pi_stale_failure", status: "requires_payment_method")))
    assert_equal "authorized", @order.reload.payment_status
    assert @order.can_accept?
  end

  test "confirmed capture enqueues Astra once only when automation is enabled" do
    previous = ENV["ASTRA_ORDER_AUTOMATION_ENABLED"]
    ENV["ASTRA_ORDER_AUTOMATION_ENABLED"] = "true"
    @order.update!(status: "submitted", payment_status: "authorized", stripe_payment_intent_id: "pi_auto")
    @order.update!(status: "accepted", payment_status: "capture_pending")
    assert_enqueued_jobs 1, only: GenerateOrderJob do
      2.times do |index|
        Payments::StripeEventHandler.call(stripe_event("evt_auto_#{index}", "payment_intent.succeeded",
          payment_intent(id: "pi_auto", status: "succeeded")))
      end
    end
    refute @order.reload.can_download?
  ensure
    ENV["ASTRA_ORDER_AUTOMATION_ENABLED"] = previous
  end

  test "rejects a previous checkout attempt after opening a new one" do
    @order.update!(checkout_attempts: 2)
    intent = payment_intent(id: "pi_old_attempt", status: "requires_capture")
    intent.metadata["checkout_attempt"] = "1"
    assert_raises(Payments::StripeEventHandler::InvalidEvent) do
      Payments::StripeEventHandler.call(stripe_event("evt_old_attempt", "payment_intent.amount_capturable_updated", intent))
    end
    assert_equal "authorization_pending", @order.reload.payment_status
  end

  test "delayed authorization uses Stripe event time for the deadline" do
    event = stripe_event("evt_delayed", "payment_intent.amount_capturable_updated",
      payment_intent(id: "pi_delayed", status: "requires_capture"))
    event.created = 4.hours.ago.to_i
    Payments::StripeEventHandler.call(event)
    assert_equal Time.zone.at(event.created) + 24.hours, @order.reload.delivery_due_at
  end

  test "a requested amount of 19 dollars does not prove a full capture" do
    @order.update!(status: "submitted", payment_status: "authorized", stripe_payment_intent_id: "pi_partial")
    @order.update!(status: "accepted", payment_status: "capture_pending")
    intent = payment_intent(id: "pi_partial", status: "succeeded")
    intent.amount_received = 100
    assert_raises(Payments::StripeEventHandler::InvalidEvent) do
      Payments::StripeEventHandler.call(stripe_event("evt_partial", "payment_intent.succeeded", intent))
    end
    assert_equal "capture_pending", @order.reload.payment_status
    refute @order.can_download?
  end

  test "orders failed by the old handler can reuse their existing checkout" do
    original = ENV["STRIPE_SECRET_KEY"]
    ENV["STRIPE_SECRET_KEY"] = "sk_test_stub"
    @order.update!(status: "failed", payment_status: "failed", stripe_payment_intent_id: "pi_legacy")
    Stripe::Checkout::Session.stub(:create, ->(*) { raise "must reuse checkout" }) do
      assert_equal "cs_test_authorize", Payments::StripeCheckout.new(@order).create.id
    end
    assert @order.reload.can_cancel?
    Payments::StripeEventHandler.call(stripe_event("evt_legacy_retry", "payment_intent.amount_capturable_updated",
      payment_intent(id: "pi_legacy", status: "requires_capture")))
    assert @order.reload.can_accept?
  ensure
    ENV["STRIPE_SECRET_KEY"] = original
  end

  test "uses the issuer capture deadline and never extends it on a replay" do
    deadline = 18.hours.from_now.change(usec: 0)
    intent = payment_intent(id: "pi_deadline", status: "requires_capture")
    intent.latest_charge[:payment_method_details][:card][:capture_before] = deadline.to_i
    Payments::StripeEventHandler.call(stripe_event("evt_deadline", "payment_intent.amount_capturable_updated", intent))
    assert_equal deadline, @order.reload.authorization_expires_at
    intent.latest_charge[:payment_method_details][:card][:capture_before] = 7.days.from_now.to_i
    Payments::StripeEventHandler.call(stripe_event("evt_deadline_replay", "payment_intent.amount_capturable_updated", intent))
    assert_equal deadline, @order.reload.authorization_expires_at
    travel_to deadline do
      refute @order.can_accept?
    end
  end

  test "retrieves the deadline when latest charge is an unexpanded Stripe id" do
    intent = payment_intent(id: "pi_charge", status: "requires_capture")
    charge = intent.latest_charge
    intent.latest_charge = "ch_authorization"
    Stripe::Charge.stub(:retrieve, ->(id) { assert_equal "ch_authorization", id; charge }) do
      Payments::StripeEventHandler.call(stripe_event("evt_charge", "payment_intent.amount_capturable_updated", intent))
    end
    assert_equal Time.zone.at(charge[:payment_method_details][:card][:capture_before]), @order.reload.authorization_expires_at
  end

  test "missing capture deadline leaves an event retryable and cannot authorize an order" do
    intent = payment_intent(id: "pi_no_deadline", status: "requires_capture")
    intent.latest_charge = nil
    assert_raises(Payments::StripeEventHandler::InvalidEvent) do
      Payments::StripeEventHandler.call(stripe_event("evt_no_deadline", "payment_intent.amount_capturable_updated", intent))
    end
    refute StripeEvent.exists?(event_id: "evt_no_deadline")
    refute @order.reload.can_accept?
    @order.update!(status: "submitted", payment_status: "authorized", authorization_expires_at: nil)
    refute @order.can_accept?
  end

  private

  def payment_intent(id:, status:, amount: 1_900)
    OpenStruct.new(
      id: id,
      status: status,
      amount: amount,
      amount_received: status == "succeeded" ? amount : 0,
      amount_capturable: status == "requires_capture" ? amount : 0,
      currency: "usd",
      latest_charge: { payment_method_details: { card: { capture_before: 2.days.from_now.to_i } } },
      metadata: { "order_public_id" => @order.public_id },
      receipt_email: @user.email
    )
  end

  def stripe_event(id, type, object)
    OpenStruct.new(id: id, type: type, created: Time.current.to_i, data: OpenStruct.new(object: object))
  end
end
