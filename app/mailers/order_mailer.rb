class OrderMailer < ApplicationMailer
  def ready
    @order = params.fetch(:order)
    @stage = params.fetch(:stage)
    @order_url = "#{ENV.fetch("APP_URL", "http://127.0.0.1:5173").delete_suffix("/")}/?order=#{@order.public_id}"
    subject = @stage == "preview" ? "Your Roblox preview is ready" : "Your Roblox map is ready"
    headers["Message-ID"] = "<scenefoundry-delivery-#{params[:delivery_id]}@scenefoundry.app>" if params[:delivery_id]
    mail(to: params[:recipients] || @order.user.email, subject: subject)
  end
end
