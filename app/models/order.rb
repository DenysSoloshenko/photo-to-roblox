class Order < ApplicationRecord
  STATUSES = %w[submitted reviewing building preview_ready ready delivered cancelled].freeze
  PAYMENT_STATUSES = %w[unpaid requested paid refunded].freeze
  SCENE_TYPES = %w[home garden park landscape venue other].freeze
  STYLES = %w[roblox_stylized faithful low_poly colorful].freeze

  belongs_to :user
  has_many :notifications, dependent: :destroy
  has_many_attached :source_photos
  has_one_attached :preview_image
  has_one_attached :result_file

  before_validation :assign_public_id, on: :create
  before_validation :set_schedule, on: :create
  before_validation :set_completed_at

  validates :public_id, presence: true, uniqueness: true
  validates :title, presence: true, length: { maximum: 120 }
  validates :status, inclusion: { in: STATUSES }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :scene_type, inclusion: { in: SCENE_TYPES }
  validates :style, inclusion: { in: STYLES }
  validates :must_preserve, :instructions, length: { maximum: 2_000 }
  validates :rights_confirmed_at, presence: true
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :preview_required_when_preview_ready
  validate :result_and_payment_required_when_ready

  after_update_commit :notify_preview_ready, if: :became_preview_ready?
  after_update_commit :notify_ready, if: :became_ready?

  def ready_for_download?
    %w[ready delivered].include?(status) && payment_status == "paid" && result_file.attached?
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def set_schedule
    self.submitted_at ||= Time.current
    self.delivery_due_at ||= submitted_at + 24.hours
  end

  def set_completed_at
    self.completed_at ||= Time.current if status.in?(%w[preview_ready ready delivered])
  end

  def preview_required_when_preview_ready
    errors.add(:preview_image, "must be attached before the preview is ready") if status.in?(%w[preview_ready ready delivered]) && !preview_image.attached?
  end

  def result_and_payment_required_when_ready
    return unless status.in?(%w[ready delivered])

    errors.add(:result_file, "must be attached before the order is ready") unless result_file.attached?
    errors.add(:payment_status, "must be paid before the map can be downloaded") unless payment_status == "paid"
  end

  def became_preview_ready?
    saved_change_to_status? && status == "preview_ready"
  end

  def notify_preview_ready
    OrderReadyNotifier.call(self, stage: :preview)
  end

  def became_ready?
    saved_change_to_status? && status == "ready"
  end

  def notify_ready
    OrderReadyNotifier.call(self, stage: :download)
  end
end
