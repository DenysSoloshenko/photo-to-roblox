require "test_helper"

class EmailDeliveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @user = User.create!(email: "outbox@example.com", display_name: "Outbox", password: "secure-password")
    @order = @user.orders.create!(title: "Outbox", rights_confirmed_at: Time.current)
  end

  test "outbox rolls back with the order transaction" do
    assert_no_difference -> { EmailDelivery.count } do
      Order.transaction do
        OrderReadyNotifier.call(@order, stage: :download)
        raise ActiveRecord::Rollback
      end
    end
    assert_equal 0, @order.notifications.count
  end

  test "a delivery has a stable message id and repeated jobs send once" do
    delivery = EmailDelivery.create!(order: @order, kind: "order_ready", recipients: [@user.email])
    first = delivery.send(:message).message_id
    assert_equal first, delivery.reload.send(:message).message_id
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      2.times { DeliverEmailJob.perform_now(delivery.id) }
    end
    assert_equal 1, delivery.reload.attempts
    assert delivery.delivered_at?
  end

  test "Solid Queue persists email work in PostgreSQL" do
    original = DeliverEmailJob.queue_adapter
    DeliverEmailJob.queue_adapter = :solid_queue
    assert_difference -> { SolidQueue::Job.count }, 1 do
      EmailDelivery.create!(order: @order, kind: "order_ready", recipients: [@user.email])
    end
    assert_equal "mailers", SolidQueue::Job.last.queue_name
  ensure
    DeliverEmailJob.queue_adapter = original
  end

  test "recovery picks up a persisted delivery whose enqueue was lost" do
    delivery = nil
    DeliverEmailJob.stub(:perform_later, ->(*) { raise "queue unavailable" }) do
      delivery = EmailDelivery.create!(order: @order, kind: "order_ready", recipients: [@user.email])
    end
    delivery.update!(created_at: 10.minutes.ago)
    assert_enqueued_with(job: DeliverEmailJob, args: [delivery.id]) { RecoverPendingWorkJob.perform_now }
  end
end
