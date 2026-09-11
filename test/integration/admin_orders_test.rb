require "test_helper"

class AdminOrdersTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_emails = ENV["ADMIN_EMAILS"]
    ENV["ADMIN_EMAILS"] = "operator@example.com"
    @customer = User.create!(email: "customer@example.com", display_name: "Customer", password: "customer-password")
    @order = @customer.orders.create!(title: "House", scene_type: "home", style: "faithful", rights_confirmed_at: Time.current)
    @order.source_photos.attach(io: StringIO.new("photo"), filename: "house.jpg", content_type: "image/jpeg")

    get "/api/v1/auth/session"
    @csrf_token = response.parsed_body.fetch("csrf_token")
    post "/api/v1/auth/register", params: {
      display_name: "Operator",
      email: "operator@example.com",
      password: "operator-password",
      password_confirmation: "operator-password",
      terms_accepted: true
    }, headers: csrf_headers, as: :json
    assert_response :created
    @csrf_token = response.parsed_body.fetch("csrf_token")
  end

  teardown do
    ENV["ADMIN_EMAILS"] = @original_admin_emails
  end

  test "operator can download sources, publish a free preview, and unlock the paid map" do
    get "/api/v1/admin/orders"
    assert_response :success
    source_url = response.parsed_body.dig("orders", 0, "source_photos", 0, "download_url")
    assert source_url.present?

    get source_url
    assert_response :success
    assert_equal "photo", response.body

    patch "/api/v1/admin/orders/#{@order.public_id}", params: {
      status: "preview_ready",
      payment_status: "unpaid",
      preview_image: fixture_file_upload("preview.png", "image/png"),
      result_file: fixture_file_upload("result.rbxlx", "application/xml")
    }, headers: csrf_headers
    assert_response :success
    assert response.parsed_body.dig("order", "preview_url").present?
    assert_nil response.parsed_body.dig("order", "result_url")

    patch "/api/v1/admin/orders/#{@order.public_id}", params: {
      status: "ready",
      payment_status: "paid"
    }, headers: csrf_headers
    assert_response :success
    assert response.parsed_body.dig("order", "result_url").present?
    assert_equal "paid", response.parsed_body.dig("order", "payment_status")
  end

  private

  def csrf_headers
    { "X-CSRF-Token" => @csrf_token }
  end
end
