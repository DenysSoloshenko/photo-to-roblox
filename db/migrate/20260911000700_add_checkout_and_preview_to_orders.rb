class AddCheckoutAndPreviewToOrders < ActiveRecord::Migration[8.0]
  def up
    add_column :orders, :preview_scene_ir, :jsonb
    add_column :orders, :stripe_checkout_session_id, :string
    add_column :orders, :stripe_payment_intent_id, :string
    add_column :orders, :checkout_started_at, :datetime
    add_index :orders, :stripe_checkout_session_id, unique: true
    add_index :orders, :stripe_payment_intent_id, unique: true
    change_column_default :orders, :price_cents, from: 900, to: 1_900
    execute <<~SQL.squish
      UPDATE orders
      SET price_cents = 1900
      WHERE price_cents = 900 AND payment_status = 'unpaid'
    SQL
  end

  def down
    change_column_default :orders, :price_cents, from: 1_900, to: 900
    remove_index :orders, :stripe_payment_intent_id
    remove_index :orders, :stripe_checkout_session_id
    remove_column :orders, :checkout_started_at
    remove_column :orders, :stripe_payment_intent_id
    remove_column :orders, :stripe_checkout_session_id
    remove_column :orders, :preview_scene_ir
  end
end
