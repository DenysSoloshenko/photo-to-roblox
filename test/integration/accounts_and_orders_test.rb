require "test_helper"

class AccountsAndOrdersTest < ActionDispatch::IntegrationTest
  setup do
    ActionMailer::Base.deliveries.clear
    get "/api/v1/auth/session"
    assert_response :success
    @csrf_token = response.parsed_body.fetch("csrf_token")
  end

  test "session exposes only Google oauth and a usable csrf token" do
    get "/api/v1/auth/session"

    assert_response :success
    assert response.parsed_body.fetch("csrf_token").present?
    providers = response.parsed_body.fetch("oauth_providers").index_by { |provider| provider.fetch("name") }
    assert_equal ["google"], providers.keys
    assert_includes [true, false], providers.fetch("google").fetch("configured")
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
    assert_equal "payment_pending", created.fetch("status")
    assert_equal "unpaid", created.fetch("payment_status")
    assert created.fetch("can_authorize")
    assert_equal 1_900, created.fetch("price_cents")
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

  test "creates a manual-capture checkout authorization and reuses it" do
    register
    user = User.find_by!(email: "denys@example.com")
    order = user.orders.create!(
      title: "Coastal park",
      scene_type: "park",
      style: "roblox_stylized",
      rights_confirmed_at: Time.current
    )
    order.source_photos.attach(io: StringIO.new("image"), filename: "park.jpg", content_type: "image/jpeg")
    original_key = ENV["STRIPE_SECRET_KEY"]
    begin
      ENV["STRIPE_SECRET_KEY"] = "sk_test_local"
      checkout = Struct.new(:id, :url).new("cs_test_order", "https://checkout.stripe.test/session")
      create_calls = 0
      create_checkout = lambda do |params, _options|
        create_calls += 1
        assert_equal "manual", params.dig(:payment_intent_data, :capture_method)
        assert_equal 1_900, params.dig(:line_items, 0, :price_data, :unit_amount)
        checkout
      end
      Stripe::Checkout::Session.stub(:create, create_checkout) do
        2.times { post "/api/v1/orders/#{order.public_id}/authorize_payment", headers: csrf_headers }
        assert_response :success
        assert_equal "authorization_pending", response.parsed_body.dig("order", "payment_status")
        assert_equal checkout.url, response.parsed_body.fetch("checkout_url")
        assert_nil response.parsed_body.dig("order", "result_url")
        assert_equal 1, create_calls
      end
    ensure
      ENV["STRIPE_SECRET_KEY"] = original_key
    end

  end

  test "keeps a paid generated result private until operator approval" do
    register
    order = User.find_by!(email: "denys@example.com").orders.create!(
      title: "Private result",
      scene_type: "garden",
      style: "roblox_stylized",
      rights_confirmed_at: Time.current
    )
    order.result_file.attach(io: StringIO.new("<roblox />"), filename: "private-result.rbxlx", content_type: "application/xml")
    order.update!(status: "submitted", payment_status: "authorized", authorized_at: Time.current, authorization_expires_at: 5.days.from_now)
    order.update!(status: "accepted", payment_status: "capture_pending", capture_requested_at: Time.current)
    order.update!(status: "building", payment_status: "paid", paid_at: Time.current, captured_at: Time.current)
    order.update!(status: "reviewing", preview_scene_ir: { "name" => "Private result", "parts" => [] })

    get "/api/v1/orders/#{order.public_id}/files/result"
    assert_response :not_found

    order.update!(status: "ready", approved_at: Time.current)
    get "/api/v1/orders/#{order.public_id}/files/result"
    assert_response :success
    assert_equal "<roblox />", response.body
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

  test "requests a password reset without revealing whether the account exists" do
    register

    assert_enqueued_emails 1 do
      post "/api/v1/auth/password/forgot", params: { email: "denys@example.com" }, headers: csrf_headers, as: :json
    end
    assert_response :accepted
    assert_equal "password_reset_instructions_sent", response.parsed_body.fetch("message")

    assert_no_enqueued_emails do
      post "/api/v1/auth/password/forgot", params: { email: "missing@example.com" }, headers: csrf_headers, as: :json
    end
    assert_response :accepted
    assert_equal "password_reset_instructions_sent", response.parsed_body.fetch("message")
  end

  test "resets the password, consumes the token, and signs the user in" do
    register
    user = User.find_by!(email: "denys@example.com")
    token = user.issue_password_reset!

    patch "/api/v1/auth/password/reset", params: {
      token: token,
      password: "a-new-secure-password",
      password_confirmation: "a-new-secure-password"
    }, headers: csrf_headers, as: :json

    assert_response :success
    assert_equal user.email, response.parsed_body.dig("user", "email")
    assert user.reload.authenticate("a-new-secure-password")
    assert_nil user.password_reset_digest

    patch "/api/v1/auth/password/reset", params: {
      token: token,
      password: "another-secure-password",
      password_confirmation: "another-secure-password"
    }, headers: { "X-CSRF-Token" => response.parsed_body.fetch("csrf_token") }, as: :json
    assert_response :unprocessable_entity
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
