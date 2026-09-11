require "test_helper"

class PaymentsStripeEventHandlerTest < ActiveSupport::TestCase
  test "unlocks the stored map only for a matching paid checkout" do
    user = User.create!(email: "buyer@example.com", display_name: "Buyer", password: "secure-password")
    order = user.orders.create!(title: "Paid garden", rights_confirmed_at: Time.current)
    xml = file_fixture("result.rbxlx").read
    order.result_file.attach(io: StringIO.new(xml), filename: "garden.rbxlx", content_type: "application/xml")
    order.update!(
      preview_scene_ir: Roblox::PreviewExtractor.new.extract(xml),
      status: "preview_ready",
      payment_status: "requested",
      stripe_checkout_session_id: "cs_test_paid"
    )
    session = Struct.new(:id, :metadata, :client_reference_id, :payment_status, :currency, :amount_total, :payment_intent)
      .new("cs_test_paid", { "order_public_id" => order.public_id }, order.public_id, "paid", "usd", 1_900, "pi_test_paid")
    event = Struct.new(:type, :data).new("checkout.session.completed", Struct.new(:object).new(session))

    assert_difference -> { Notification.count }, 1 do
      Payments::StripeEventHandler.call(event)
    end

    order.reload
    assert_equal "paid", order.payment_status
    assert_equal "ready", order.status
    assert_equal "pi_test_paid", order.stripe_payment_intent_id
    assert order.ready_for_download?
  end
end
