module OAuth
  class IdentityResolver
    def self.call(provider, profile)
      new(provider, profile).call
    end

    def initialize(provider, profile)
      @provider = provider
      @profile = profile
    end

    def call
      raise Provider::Error, "A verified email address and identity are required" unless profile.email_verified == true && profile.email.present? && profile.uid.present?

      User.transaction do
        identity = Identity.includes(:user).find_by(provider: provider, uid: profile.uid)
        user = identity&.user || User.find_by("lower(email) = ?", profile.email.strip.downcase) || User.create!(
          email: profile.email,
          display_name: profile.name.presence || profile.email.split("@").first,
          terms_accepted_at: Time.current
        )
        user.with_lock do
          if user.email_verified_at.blank?
            unless user.email == profile.email.strip.downcase
              raise Provider::Error, "Verified provider email does not match this account"
            end
            # Someone may have pre-registered the real owner's email. Remove
            # their password/reset token and invalidate all existing sessions.
            user.update!(email_verified_at: Time.current, password_digest: nil,
              password_reset_digest: nil, password_reset_sent_at: nil,
              session_version: user.session_version + 1)
          end
          user.identities.create!(provider: provider, uid: profile.uid, email: profile.email) unless identity
        end
        user
      end
    rescue ActiveRecord::RecordNotUnique
      Identity.includes(:user).find_by!(provider: provider, uid: profile.uid).user
    end

    private

    attr_reader :provider, :profile
  end
end
