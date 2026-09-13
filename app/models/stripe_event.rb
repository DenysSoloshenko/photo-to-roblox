class StripeEvent < ApplicationRecord
  validates :event_id, :event_type, :processed_at, presence: true
  validates :event_id, uniqueness: true
end
