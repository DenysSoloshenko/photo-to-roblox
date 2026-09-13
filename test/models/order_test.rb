require "test_helper"

class OrderTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "state@example.com", display_name: "State", password: "secure-password")
    @order = @user.orders.create!(title: "Stateful order", rights_confirmed_at: Time.current)
  end

  test "rejects unsafe status and payment jumps" do
    refute @order.update(status: "ready", payment_status: "paid")
    assert_includes @order.errors[:status].join, "cannot transition"
    assert_includes @order.errors[:payment_status].join, "cannot transition"
  end

  test "exposes actions from the persisted workflow state" do
    assert @order.can_authorize?
    assert @order.can_cancel?
    refute @order.can_accept?

    @order.update!(status: "submitted", payment_status: "authorized", authorized_at: Time.current, authorization_expires_at: 5.days.from_now)
    assert @order.can_accept?
    assert @order.can_decline?
    refute @order.can_authorize?
  end

  test "expired authorization cannot be accepted" do
    @order.update!(status: "submitted", payment_status: "authorized", authorized_at: 7.days.ago, authorization_expires_at: 1.minute.ago)

    refute @order.can_accept?
    assert @order.can_decline?
  end
end
