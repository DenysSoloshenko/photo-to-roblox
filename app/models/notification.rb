class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :order

  validates :kind, :title, :body, presence: true
  validates :kind, uniqueness: { scope: :order_id }

  def read?
    read_at.present?
  end
end
