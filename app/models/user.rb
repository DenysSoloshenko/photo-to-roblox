class User < ApplicationRecord
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

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

end
