class Order < ApplicationRecord
  PRICE_CENTS = 1_900
  STATUSES = %w[payment_pending submitted accepted building reviewing preview_ready ready delivered declined cancelled failed].freeze
  PAYMENT_STATUSES = %w[unpaid authorization_pending authorized capture_pending paid released refund_pending refunded failed].freeze
  STATUS_TRANSITIONS = {
    "payment_pending" => %w[submitted cancelled failed],
    "submitted" => %w[accepted declined cancelled failed],
    "accepted" => %w[building declined cancelled failed],
    "building" => %w[reviewing failed],
    "reviewing" => %w[preview_ready ready failed],
    "preview_ready" => %w[ready delivered failed],
    "ready" => %w[delivered failed],
    "delivered" => %w[failed],
    "declined" => %w[failed],
    "cancelled" => %w[failed],
    "failed" => %w[payment_pending submitted building]
  }.freeze
  PAYMENT_STATUS_TRANSITIONS = {
    "unpaid" => %w[authorization_pending authorized released failed],
    "authorization_pending" => %w[unpaid authorized released failed],
    "authorized" => %w[capture_pending released failed],
    "capture_pending" => %w[paid released failed],
    "paid" => %w[refund_pending refunded failed],
    "released" => [],
    "refund_pending" => %w[refunded failed],
    "refunded" => [],
    "failed" => %w[unpaid authorization_pending authorized capture_pending paid released refunded]
  }.freeze
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
  validates :generation_attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :status_transition_is_allowed, on: :update
  validate :payment_status_transition_is_allowed, on: :update
  validate :preview_required_when_preview_ready
  validate :result_and_payment_required_when_ready

  after_update_commit :notify_preview_ready, if: :became_preview_ready?
  after_update_commit :notify_ready, if: :became_ready?
  after_update_commit :enqueue_premium_generation, if: :became_paid_building?

  def ready_for_download?
    %w[ready delivered].include?(status) && payment_status == "paid" && result_file.attached?
  end

  def can_authorize?
    status == "payment_pending" && payment_status.in?(%w[unpaid authorization_pending])
  end

  def can_cancel?
    status.in?(%w[payment_pending submitted]) && !payment_status.in?(%w[capture_pending paid refund_pending refunded])
  end

  def can_accept?
    (status == "submitted" && payment_status == "authorized" && !authorization_expired?) ||
      (status == "accepted" && payment_status == "capture_pending")
  end

  def can_decline?
    status.in?(%w[submitted declined]) && payment_status == "authorized"
  end

  def can_approve?
    status == "reviewing" && payment_status == "paid" && preview_scene_ir.present? && result_file.attached?
  end

  def can_download?
    ready_for_download?
  end

  def authorization_expired?
    authorization_expires_at.present? && authorization_expires_at <= Time.current
  end

  private

  def status_transition_is_allowed
    return unless will_save_change_to_status?

    previous, next_status = status_change_to_be_saved
    return if previous.blank? || STATUS_TRANSITIONS.fetch(previous, []).include?(next_status)

    errors.add(:status, "cannot transition from #{previous} to #{next_status}")
  end

  def payment_status_transition_is_allowed
    return unless will_save_change_to_payment_status?

    previous, next_status = payment_status_change_to_be_saved
    return if previous.blank? || PAYMENT_STATUS_TRANSITIONS.fetch(previous, []).include?(next_status)

    errors.add(:payment_status, "cannot transition from #{previous} to #{next_status}")
  end

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
    return unless status.in?(%w[preview_ready ready delivered])

    errors.add(:preview_scene_ir, "must be generated before the preview is ready") if preview_scene_ir.blank?
    errors.add(:result_file, "must be attached before the preview is ready") unless result_file.attached?
  end

  def result_and_payment_required_when_ready
    return unless status.in?(%w[ready delivered])

    errors.add(:result_file, "must be attached before the order is ready") unless result_file.attached?
    unless payment_status.in?(%w[paid refund_pending refunded])
      errors.add(:payment_status, "must be paid before the order can be approved")
    end
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

  def became_paid_building?
    saved_change_to_status? && status == "building" && payment_status == "paid"
  end

  def enqueue_premium_generation
    GenerateOrderJob.perform_later(id)
  end
end
