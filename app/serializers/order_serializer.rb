class OrderSerializer
  def initialize(order, admin: false)
    @order = order
    @admin = admin
  end

  def as_json(*)
    data = {
      public_id: order.public_id,
      status: order.status,
      workflow_state: order.workflow_state,
      payment_status: order.payment_status,
      title: order.title,
      scene_type: order.scene_type,
      style: order.style,
      must_preserve: order.must_preserve,
      instructions: order.instructions,
      price_cents: order.price_cents,
      currency: order.currency,
      submitted_at: order.submitted_at.iso8601,
      delivery_due_at: order.delivery_due_at.iso8601,
      completed_at: order.completed_at&.iso8601,
      purchase_requested_at: order.purchase_requested_at&.iso8601,
      paid_at: order.paid_at&.iso8601,
      authorization_expires_at: order.authorization_expires_at&.iso8601,
      authorized_at: order.authorized_at&.iso8601,
      capture_requested_at: order.capture_requested_at&.iso8601,
      captured_at: order.captured_at&.iso8601,
      released_at: order.released_at&.iso8601,
      refunded_at: order.refunded_at&.iso8601,
      generation_started_at: order.generation_started_at&.iso8601,
      generation_finished_at: order.generation_finished_at&.iso8601,
      generation_attempts: order.generation_attempts,
      can_authorize: order.can_authorize?,
      can_cancel: order.can_cancel?,
      can_accept: admin && order.can_accept?,
      can_decline: admin && order.can_decline?,
      can_approve: admin && order.can_approve?,
      can_download: order.can_download?,
      rights_confirmed: order.rights_confirmed_at.present?,
      source_photos: order.source_photos.map { |photo| attachment_json(photo) },
      preview_url: order.preview_image.attached? ? file_url("preview") : nil,
      preview_scene_ir: preview_available? ? order.preview_scene_ir : nil,
      result_url: order.ready_for_download? ? file_url("result") : nil
    }
    data[:generation_metrics] = order.generation_metrics if admin || order.status.in?(%w[ready delivered])
    if admin
      data.merge!(
        user: { email: order.user.email, display_name: order.user.display_name },
        admin_notes: order.admin_notes,
        payment_error: order.payment_error,
        generation_error: order.generation_error
      )
    end
    data
  end

  private

  attr_reader :order, :admin

  def attachment_json(attachment)
    data = { filename: attachment.filename.to_s, byte_size: attachment.byte_size, content_type: attachment.content_type }
    data.merge!(id: attachment.id, download_url: "/api/v1/admin/orders/#{order.public_id}/files/source/#{attachment.id}") if admin
    data
  end

  def file_url(kind)
    "/api/v1/orders/#{order.public_id}/files/#{kind}"
  end

  def preview_available?
    admin || (order.preview_scene_ir.present? && order.status.in?(%w[preview_ready ready delivered]))
  end
end
