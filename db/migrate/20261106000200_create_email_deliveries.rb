class CreateEmailDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :email_deliveries do |t|
      t.references :order, null: false, foreign_key: true
      t.string :kind, null: false
      t.jsonb :recipients, null: false, default: []
      t.integer :attempts, null: false, default: 0
      t.datetime :delivered_at
      t.datetime :last_attempt_at
      t.string :last_error
      t.timestamps
    end
    add_index :email_deliveries, [:order_id, :kind], unique: true
    add_index :email_deliveries, [:delivered_at, :created_at]
  end
end
