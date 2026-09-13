class AddReservedPaymentWorkflow < ActiveRecord::Migration[8.0]
  def up
    change_column_default :orders, :status, from: "submitted", to: "payment_pending"
    change_column_default :orders, :payment_status, from: "unpaid", to: "unpaid"

    add_column :orders, :stripe_checkout_url, :text
    add_column :orders, :checkout_attempts, :integer, null: false, default: 0
    add_column :orders, :authorization_expires_at, :datetime
    add_column :orders, :authorized_at, :datetime
    add_column :orders, :capture_requested_at, :datetime
    add_column :orders, :captured_at, :datetime
    add_column :orders, :released_at, :datetime
    add_column :orders, :refund_requested_at, :datetime
    add_column :orders, :refunded_at, :datetime
    add_column :orders, :payment_failed_at, :datetime
    add_column :orders, :payment_error, :text
    add_column :orders, :accepted_at, :datetime
    add_column :orders, :declined_at, :datetime
    add_column :orders, :cancelled_at, :datetime
    add_column :orders, :approved_at, :datetime
    add_column :orders, :generation_started_at, :datetime
    add_column :orders, :generation_finished_at, :datetime
    add_column :orders, :generation_attempts, :integer, null: false, default: 0
    add_column :orders, :generation_metrics, :jsonb, null: false, default: {}
    add_column :orders, :generation_error, :text

    create_table :stripe_events do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :order_public_id
      t.datetime :stripe_created_at
      t.datetime :processed_at, null: false
      t.timestamps
    end

    add_index :stripe_events, :event_id, unique: true
    add_index :stripe_events, %i[order_public_id processed_at]

    execute <<~SQL.squish
      UPDATE orders
      SET status = 'payment_pending'
      WHERE status = 'submitted' AND payment_status = 'unpaid'
    SQL
  end

  def down
    drop_table :stripe_events

    remove_column :orders, :generation_error
    remove_column :orders, :generation_metrics
    remove_column :orders, :generation_attempts
    remove_column :orders, :generation_finished_at
    remove_column :orders, :generation_started_at
    remove_column :orders, :approved_at
    remove_column :orders, :cancelled_at
    remove_column :orders, :declined_at
    remove_column :orders, :accepted_at
    remove_column :orders, :payment_failed_at
    remove_column :orders, :payment_error
    remove_column :orders, :refunded_at
    remove_column :orders, :refund_requested_at
    remove_column :orders, :released_at
    remove_column :orders, :captured_at
    remove_column :orders, :capture_requested_at
    remove_column :orders, :authorized_at
    remove_column :orders, :authorization_expires_at
    remove_column :orders, :stripe_checkout_url
    remove_column :orders, :checkout_attempts

    change_column_default :orders, :status, from: "payment_pending", to: "submitted"
  end
end
