class OrderSerializer
  def initialize(order, admin: false)
    @order = order
    @admin = admin
  end

  def as_json(*)
    data = {
      public_id: order.public_id,
      status: order.status,
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
      rights_confirmed: order.rights_confirmed_at.present?,
      source_photos: order.source_photos.map { |photo| attachment_json(photo) },
      preview_url: order.preview_image.attached? ? file_url("preview") : nil,
      result_url: order.ready_for_download? ? file_url("result") : nil
    }
    data.merge!(user: { email: order.user.email, display_name: order.user.display_name }, admin_notes: order.admin_notes) if admin
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
end
