class Identity < ApplicationRecord
  PROVIDERS = %w[google github discord].freeze

  belongs_to :user

  validates :provider, inclusion: { in: PROVIDERS }
  validates :uid, presence: true, uniqueness: { scope: :provider }
end
