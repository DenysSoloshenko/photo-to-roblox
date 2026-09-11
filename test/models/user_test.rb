require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes email and hashes passwords" do
    user = User.create!(email: " Person@Example.COM ", display_name: "Person", password: "very-secure-password")

    assert_equal "person@example.com", user.email
    refute_equal "very-secure-password", user.password_digest
    assert user.authenticate("very-secure-password")
  end

  test "allows oauth-only accounts" do
    user = User.create!(email: "oauth@example.com", display_name: "OAuth Person", terms_accepted_at: Time.current)

    assert user.oauth_only?
  end
end
