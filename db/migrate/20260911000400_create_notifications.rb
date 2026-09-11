class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.datetime :read_at
      t.timestamps
    end

    add_index :notifications, %i[user_id read_at created_at], name: "index_notifications_for_inbox"
    add_index :notifications, %i[order_id kind], unique: true
  end
end
