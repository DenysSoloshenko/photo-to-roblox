class AddRightsConfirmedAtToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :rights_confirmed_at, :datetime, null: false
  end
end
