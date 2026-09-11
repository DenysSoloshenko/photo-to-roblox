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
      existing = Identity.includes(:user).find_by(provider: provider, uid: profile.uid)
      return existing.user if existing
      raise Provider::Error, "A verified email address is required" unless profile.email_verified && profile.email.present?

      User.transaction do
        user = User.find_by("lower(email) = ?", profile.email.downcase) || User.create!(
          email: profile.email,
          display_name: profile.name.presence || profile.email.split("@").first,
          terms_accepted_at: Time.current
        )
        user.identities.create!(provider: provider, uid: profile.uid, email: profile.email)
        user
      end
    rescue ActiveRecord::RecordNotUnique
      Identity.includes(:user).find_by!(provider: provider, uid: profile.uid).user
    end

    private

    attr_reader :provider, :profile
  end
end
