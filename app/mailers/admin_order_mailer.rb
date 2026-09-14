class AdminOrderMailer < ApplicationMailer
  def new_order
    @order = params.fetch(:order)
    @admin_url = ENV.fetch("APP_URL", "http://127.0.0.1:5173").delete_suffix("/")
    @source_links = @order.source_photos.map do |photo|
      {
        filename: photo.filename.to_s,
        url: "#{@admin_url}/api/v1/admin/orders/#{@order.public_id}/files/source/#{photo.id}"
      }
    end

    mail(
      to: params.fetch(:recipients),
      subject: "New SceneFoundry order: #{@order.title}"
    )
  end
end
