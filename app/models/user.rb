require "digest"

class User < ApplicationRecord
  PASSWORD_RESET_TTL = 30.minutes

  has_secure_password validations: false

  has_many :identities, dependent: :destroy
  has_many :orders, dependent: :restrict_with_error
  has_many :notifications, dependent: :destroy

  before_validation :normalize_email

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { case_sensitive: false }
  validates :display_name, presence: true, length: { maximum: 80 }
  validates :password, length: { minimum: 10, maximum: 128 }, allow_nil: true

  def admin?
    ENV.fetch("ADMIN_EMAILS", "").split(",").map { |value| value.strip.downcase }.include?(email.downcase)
  end

  def oauth_only?
    password_digest.blank?
  end

  def issue_password_reset!
    token = SecureRandom.urlsafe_base64(32)
    update!(
      password_reset_digest: self.class.password_reset_digest(token),
      password_reset_sent_at: Time.current
    )
    token
  end

  def reset_password!(password:, password_confirmation:)
    assign_attributes(
      password: password,
      password_confirmation: password_confirmation,
      password_reset_digest: nil,
      password_reset_sent_at: nil,
      session_version: session_version + 1
    )
    save
  end

  def self.find_for_password_reset(token)
    return if token.blank?

    where("password_reset_sent_at >= ?", PASSWORD_RESET_TTL.ago)
      .find_by(password_reset_digest: password_reset_digest(token))
  end

  def self.password_reset_digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

end
