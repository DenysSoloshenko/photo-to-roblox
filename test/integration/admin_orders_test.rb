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

  test "operator captures an authorized order, uploads result, and approves delivery" do
    get "/api/v1/admin/orders"
    assert_response :success
    source_url = response.parsed_body.dig("orders", 0, "source_photos", 0, "download_url")
    assert source_url.present?

    get source_url
    assert_response :success
    assert_equal "photo", response.body

    @order.update!(
      status: "submitted",
      payment_status: "authorized",
      stripe_payment_intent_id: "pi_authorized",
      authorized_at: Time.current,
      authorization_expires_at: 5.days.from_now
    )
    original_key = ENV["STRIPE_SECRET_KEY"]
    ENV["STRIPE_SECRET_KEY"] = "sk_test_local"
    intent = Struct.new(:id, :status, :amount, :currency, :metadata, :receipt_email)
      .new("pi_authorized", "succeeded", 1_900, "usd", { "order_public_id" => @order.public_id }, @customer.email)
    assert_no_enqueued_jobs only: GenerateOrderJob do
      Stripe::PaymentIntent.stub(:capture, intent) do
        post "/api/v1/admin/orders/#{@order.public_id}/accept", headers: csrf_headers
      end
    end
    assert_response :success
    assert_equal "building", response.parsed_body.dig("order", "status")
    assert_equal "in_progress", response.parsed_body.dig("order", "workflow_state")
    assert_equal "paid", response.parsed_body.dig("order", "payment_status")

    patch "/api/v1/admin/orders/#{@order.public_id}", params: {
      preview_image: fixture_file_upload("preview.png", "image/png"),
      result_file: fixture_file_upload("result.rbxlx", "application/xml")
    }, headers: csrf_headers
    assert_response :success
    assert_equal "reviewing", response.parsed_body.dig("order", "status")
    assert_equal 1, response.parsed_body.dig("order", "preview_scene_ir", "stats", "part_count")
    assert_nil response.parsed_body.dig("order", "result_url")

    assert_difference -> { Notification.count }, 1 do
      post "/api/v1/admin/orders/#{@order.public_id}/approve", headers: csrf_headers
    end
    assert_response :success
    assert_equal "completed", response.parsed_body.dig("order", "workflow_state")
    assert response.parsed_body.dig("order", "result_url").present?
  ensure
    ENV["STRIPE_SECRET_KEY"] = original_key
  end

  test "operator decline releases an uncaptured authorization" do
    @order.update!(
      status: "submitted",
      payment_status: "authorized",
      stripe_payment_intent_id: "pi_decline",
      authorized_at: Time.current,
      authorization_expires_at: 5.days.from_now
    )
    original_key = ENV["STRIPE_SECRET_KEY"]
    ENV["STRIPE_SECRET_KEY"] = "sk_test_local"
    intent = Struct.new(:id, :status, :amount, :currency, :metadata, :receipt_email)
      .new("pi_decline", "canceled", 1_900, "usd", { "order_public_id" => @order.public_id }, @customer.email)
    Stripe::PaymentIntent.stub(:cancel, intent) do
      post "/api/v1/admin/orders/#{@order.public_id}/decline", headers: csrf_headers
    end

    assert_response :success
    assert_equal "declined", response.parsed_body.dig("order", "status")
    assert_equal "released", response.parsed_body.dig("order", "payment_status")
    assert response.parsed_body.dig("order", "released_at").present?
  ensure
    ENV["STRIPE_SECRET_KEY"] = original_key
  end

  test "operator can inspect the real transactional email templates" do
    get "/api/v1/admin/email_previews/new_order"
    assert_response :success
    assert_includes response.body, "New order to review"
    assert_includes response.body, "pacific-centre.jpg"

    get "/api/v1/admin/email_previews/password_reset"
    assert_response :success
    assert_includes response.body, "Reset your password"

    get "/api/v1/admin/email_previews/preview_ready"
    assert_response :success
    assert_includes response.body, "Your free preview is ready"

    get "/api/v1/admin/email_previews/map_ready"
    assert_response :success
    assert_includes response.body, "Your map is ready"
  end

  private

  def csrf_headers
    { "X-CSRF-Token" => @csrf_token }
  end
end
