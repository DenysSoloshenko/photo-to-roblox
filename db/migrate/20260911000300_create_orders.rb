class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :status, null: false, default: "submitted"
      t.string :payment_status, null: false, default: "unpaid"
      t.string :title, null: false
      t.string :scene_type, null: false, default: "other"
      t.string :style, null: false, default: "roblox_stylized"
      t.text :must_preserve
      t.text :instructions
      t.integer :price_cents, null: false, default: 900
      t.string :currency, null: false, default: "USD"
      t.datetime :submitted_at, null: false
      t.datetime :delivery_due_at, null: false
      t.datetime :completed_at
      t.datetime :purchase_requested_at
      t.datetime :paid_at
      t.text :admin_notes
      t.timestamps
    end

    add_index :orders, :public_id, unique: true
    add_index :orders, %i[user_id created_at]
    add_index :orders, %i[status delivery_due_at]
    add_index :orders, %i[payment_status created_at]
  end
end
