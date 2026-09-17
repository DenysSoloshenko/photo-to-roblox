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
  test "verified Google login removes credentials and sessions from a pre-registered account" do
    user = User.create!(email: "owner@example.com", display_name: "Impostor", password: "attacker-password")
    old_token = user.issue_password_reset!
    profile = OAuth::Provider::Profile.new(uid: "real-owner", email: user.email, email_verified: true, name: "Owner")

    assert_equal user, OAuth::IdentityResolver.call("google", profile)
    user.reload
    assert user.email_verified_at
    assert_nil user.password_digest
    assert_nil User.find_for_password_reset(old_token)
    assert_equal 1, user.session_version
    OAuth::IdentityResolver.call("google", profile)
    assert_equal 1, user.reload.session_version
  end

  test "unverified repeat provider login is rejected" do
    profile = OAuth::Provider::Profile.new(uid: "repeat", email: "repeat@example.com", email_verified: true, name: "Owner")
    OAuth::IdentityResolver.call("google", profile)
    profile = OAuth::Provider::Profile.new(uid: "repeat", email: "repeat@example.com", email_verified: false, name: "Owner")
    assert_raises(OAuth::Provider::Error) { OAuth::IdentityResolver.call("google", profile) }
  end

end
