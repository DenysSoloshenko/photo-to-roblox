require "test_helper"

class OrderReadyNotifierTest < ActiveSupport::TestCase
  test "a failed email can be retried without duplicating the notification or successful email" do
    user = User.create!(email: "retry-mail@example.com", display_name: "Buyer", password: "secure-password")
    order = user.orders.create!(title: "Mail retry", rights_confirmed_at: Time.current)
    mail = Minitest::Mock.new
    mail.expect(:ready, mail)
    mail.expect(:deliver_now, nil) { raise Email::ResendDeliveryMethod::DeliveryError, "temporary outage" }
    OrderReadyNotifier.call(order, stage: :download)
    delivery = EmailDelivery.find_by!(order: order, kind: "order_ready")
    OrderMailer.stub(:with, mail) do
      assert_raises(Email::ResendDeliveryMethod::DeliveryError) { delivery.deliver! }
    end
    assert_equal 1, order.notifications.count

    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      OrderReadyNotifier.call(order, stage: :download)
      delivery.deliver!
    end
    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      OrderReadyNotifier.call(order, stage: :download)
      delivery.deliver!
    end
    assert_equal 1, order.notifications.count
  end
end
