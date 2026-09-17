class AddEmailVerificationToUsers < ActiveRecord::Migration[8.0]
  def change
    # Do not infer ownership from an address supplied during registration.
    add_column :users, :email_verified_at, :datetime
  end
end
