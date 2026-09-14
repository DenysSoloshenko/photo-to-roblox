require "test_helper"

class OAuthIdentityResolverTest < ActiveSupport::TestCase
  test "creates an oauth-only user from a verified profile" do
    profile = OAuth::Provider::Profile.new(uid: "provider-1", email: "social@example.com", email_verified: true, name: "Social User")

    user = OAuth::IdentityResolver.call("google", profile)

    assert_equal "social@example.com", user.email
    assert user.oauth_only?
    assert_equal "provider-1", user.identities.find_by!(provider: "google").uid
  end

  test "refuses to link an unverified email" do
    profile = OAuth::Provider::Profile.new(uid: "provider-2", email: "unsafe@example.com", email_verified: false, name: "Unsafe")

    assert_raises(OAuth::Provider::Error) { OAuth::IdentityResolver.call("google", profile) }
  end
end
