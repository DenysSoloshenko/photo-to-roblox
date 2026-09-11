require "test_helper"

class AccountsAndOrdersTest < ActionDispatch::IntegrationTest
  setup do
    ActionMailer::Base.deliveries.clear
    get "/api/v1/auth/session"
    assert_response :success
    @csrf_token = response.parsed_body.fetch("csrf_token")
  end

  test "registers, persists a free order, and lists it for its owner" do
    register

    photo = fixture_file_upload("source.jpg", "image/jpeg")
    post "/api/v1/orders",
      params: {
        title: "Family garden",
        scene_type: "garden",
        style: "faithful",
        must_preserve: "Central path and old tree",
        instructions: "Keep it playable",
        rights_confirmed: "true",
        source_photos: [photo]
      },
      headers: csrf_headers

    assert_response :created
    created = response.parsed_body.fetch("order")
    assert_equal "submitted", created.fetch("status")
    assert_equal "unpaid", created.fetch("payment_status")
    assert_equal 900, created.fetch("price_cents")
    assert_nil created.fetch("result_url")
    assert Order.find_by!(public_id: created.fetch("public_id")).source_photos.attached?

    get "/api/v1/orders"
    assert_response :success
    assert_equal ["Family garden"], response.parsed_body.fetch("orders").pluck("title")
  end

  test "rejects state-changing requests without csrf token" do
    post "/api/v1/auth/register", params: {
      display_name: "Denys",
      email: "denys@example.com",
      password: "very-secure-password",
      password_confirmation: "very-secure-password",
      terms_accepted: true
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "invalid_csrf_token", response.parsed_body.fetch("error")
  end

  test "notifies the customer when a free preview is ready and gates the map until paid" do
    register
    user = User.find_by!(email: "denys@example.com")
    order = user.orders.create!(
      title: "Coastal park",
      scene_type: "park",
      style: "roblox_stylized",
      rights_confirmed_at: Time.current
    )
    order.source_photos.attach(io: StringIO.new("image"), filename: "park.jpg", content_type: "image/jpeg")
    order.preview_image.attach(io: StringIO.new("preview"), filename: "preview.png", content_type: "image/png")
    order.result_file.attach(io: StringIO.new("<roblox />"), filename: "park.rbxlx", content_type: "application/xml")

    assert_difference -> { Notification.count }, 1 do
      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        order.update!(status: "preview_ready")
      end
    end

    post "/api/v1/orders/#{order.public_id}/purchase", headers: csrf_headers
    assert_response :success
    assert_equal "requested", response.parsed_body.dig("order", "payment_status")
    assert_nil response.parsed_body.dig("order", "result_url")

    order.update!(payment_status: "paid", paid_at: Time.current, status: "ready")
    get "/api/v1/orders/#{order.public_id}"
    assert_response :success
    assert_equal "/api/v1/orders/#{order.public_id}/files/result", response.parsed_body.dig("order", "result_url")
  end

  test "logs in an existing password account and rotates the csrf token" do
    register
    delete "/api/v1/auth/logout", headers: csrf_headers
    assert_response :success

    get "/api/v1/auth/session"
    logged_out_token = response.parsed_body.fetch("csrf_token")
    post "/api/v1/auth/login", params: { email: "DENYS@example.com", password: "very-secure-password" }, headers: { "X-CSRF-Token" => logged_out_token }, as: :json

    assert_response :success
    assert_equal "denys@example.com", response.parsed_body.dig("user", "email")
    refute_equal logged_out_token, response.parsed_body.fetch("csrf_token")
  end

  private

  def register
    post "/api/v1/auth/register", params: {
      display_name: "Denys",
      email: "Denys@example.com",
      password: "very-secure-password",
      password_confirmation: "very-secure-password",
      terms_accepted: true
    }, headers: csrf_headers, as: :json
    assert_response :created
    @csrf_token = response.parsed_body.fetch("csrf_token")
  end

  def csrf_headers
    { "X-CSRF-Token" => @csrf_token }
  end
end
