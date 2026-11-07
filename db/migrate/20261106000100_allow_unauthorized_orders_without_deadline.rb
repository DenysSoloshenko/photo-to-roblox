class AllowUnauthorizedOrdersWithoutDeadline < ActiveRecord::Migration[8.0]
  def up
    change_column_null :orders, :delivery_due_at, true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Orders without authorization have no delivery deadline"
  end
end
