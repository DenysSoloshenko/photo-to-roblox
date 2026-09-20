require Rails.root.join("app/services/email/resend_delivery_method")

ActionMailer::Base.add_delivery_method(
  :resend_api,
  Email::ResendDeliveryMethod,
  api_key: ENV["RESEND_API_KEY"],
  api_url: ENV.fetch("RESEND_API_URL", Email::ResendDeliveryMethod::API_URL),
  open_timeout: ENV.fetch("RESEND_OPEN_TIMEOUT_SECONDS", 5).to_i,
  read_timeout: ENV.fetch("RESEND_READ_TIMEOUT_SECONDS", 15).to_i
)
