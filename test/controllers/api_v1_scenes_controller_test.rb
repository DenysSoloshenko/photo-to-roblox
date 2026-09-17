require "test_helper"

class ApiV1ScenesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @original_admin_emails = ENV["ADMIN_EMAILS"]
    ENV["ADMIN_EMAILS"] = "lab-admin@example.com"
    @spec = JSON.parse(Rails.root.join("examples/park.json").read)
    get "/api/v1/auth/session"
    @csrf_token = response.parsed_body.fetch("csrf_token")
    post "/api/v1/auth/register", params: {
      display_name: "Lab Admin",
      email: "lab-admin@example.com",
      password: "lab-admin-password",
      password_confirmation: "lab-admin-password",
      terms_accepted: true
    }, headers: csrf_headers, as: :json
    assert_response :created
    User.find_by!(email: "lab-admin@example.com").update!(email_verified_at: Time.current)
    @csrf_token = response.parsed_body.fetch("csrf_token")
  end

  def teardown
    ENV["ADMIN_EMAILS"] = @original_admin_emails
  end

  test "compiles edited JSON without embedding a map by default" do
    post "/api/v1/scenes/compile", params: { scene_spec: @spec }, headers: csrf_headers, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Riverside Park", body.dig("scene_ir", "name")
    assert body.dig("scene_ir", "stats", "part_count").positive?
    refute body.key?("roblox_file")
    assert_equal false, body.dig("metrics", "map_ready")
    refute body.fetch("metrics").key?("export_ms")
    refute body.fetch("metrics").key?("rbxlx_bytes")
  end

  test "compiles edited JSON with an embedded ready map when requested" do
    post "/api/v1/scenes/compile", params: { scene_spec: @spec, include_map: true }, headers: csrf_headers, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    artifact = body.fetch("roblox_file")
    xml = Base64.strict_decode64(artifact.fetch("data"))

    assert_match(/<roblox\b/, xml)
    assert_equal xml.bytesize, artifact.fetch("byte_size")
    assert_equal body.dig("scene_ir", "spec_digest"), artifact.fetch("spec_digest")
    assert_equal true, body.dig("metrics", "map_ready")
    assert_operator body.dig("metrics", "export_ms"), :>=, 0
    assert_equal artifact.fetch("byte_size"), body.dig("metrics", "rbxlx_bytes")
  end

  test "serves a compiled development example" do
    get "/api/v1/scenes/examples/park"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @spec, body.fetch("scene_spec")
    assert_equal "Riverside Park", body.dig("scene_ir", "name")
    refute body.key?("roblox_file")
    assert_equal false, body.dig("metrics", "map_ready")
  end

  test "takes an astra upload through analysis and returns a ready map" do
    fake_analyzer = Object.new
    spec = @spec
    fake_analyzer.define_singleton_method(:analyze) do |bytes:, mime_type:, filename:, hint:|
      raise "upload was not forwarded" unless bytes == "new-photo-bytes" && mime_type == "image/jpeg"
      raise "metadata was not forwarded" unless filename == "new-yard.jpg" && hint == "keep the large tree"

      {
        scene_spec: spec,
        metrics: { "vision_model" => "fake-vision", "vision_ms" => 123.4, "api_cost_usd" => 0.0042 }
      }
    end
    upload = Rack::Test::UploadedFile.new(StringIO.new("new-photo-bytes"), "image/jpeg", original_filename: "new-yard.jpg")
    requested_quality_modes = []
    analyzer_factory = lambda do |quality_mode|
      requested_quality_modes << quality_mode
      fake_analyzer
    end

    Vision::SceneAnalyzer.stub(:for_quality, analyzer_factory) do
      post "/api/v1/scenes/analyze", params: {
        photo: upload,
        hint: "keep the large tree",
        quality_mode: "astra_max",
        include_map: "true"
      }, headers: csrf_headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    artifact = body.fetch("roblox_file")
    xml = Base64.strict_decode64(artifact.fetch("data"))

    assert_equal ["astra_max"], requested_quality_modes
    assert_equal "Riverside Park", body.dig("scene_ir", "name")
    assert_equal "fake-vision", body.dig("metrics", "vision_model")
    assert_equal 0.0042, body.dig("metrics", "api_cost_usd")
    assert body.dig("metrics", "total_ms").positive?
    assert body.dig("metrics", "order_id").present?
    assert_match(/<roblox\b/, xml)
    assert_equal true, body.dig("metrics", "map_ready")
    assert_operator body.dig("metrics", "export_ms"), :>=, 0
    assert_equal xml.bytesize, body.dig("metrics", "rbxlx_bytes")
  end

  test "normalizes an over-budget vision scene before compilation" do
    oversized = Marshal.load(Marshal.dump(@spec))
    oversized.fetch("groups").each { |group| group["count"] = 200 }
    fake_analyzer = Object.new
    fake_analyzer.define_singleton_method(:analyze) do |**|
      { scene_spec: oversized, metrics: { "vision_model" => "fake-vision", "vision_ms" => 50.0 } }
    end
    upload = Rack::Test::UploadedFile.new(StringIO.new("new-photo-bytes"), "image/jpeg", original_filename: "large-scene.jpg")
    requested_quality_modes = []
    analyzer_factory = lambda do |quality_mode|
      requested_quality_modes << quality_mode
      fake_analyzer
    end

    Vision::SceneAnalyzer.stub(:for_quality, analyzer_factory) do
      post "/api/v1/scenes/analyze", params: { photo: upload }, headers: csrf_headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal ["terra"], requested_quality_modes
    assert body.dig("metrics", "budget_adjusted")
    assert_operator body.dig("metrics", "removed_group_instances"), :>, 0
    assert_operator body.dig("scene_ir", "stats", "part_count"), :<=, 1_500
    refute body.key?("roblox_file")
    assert_equal false, body.dig("metrics", "map_ready")
  end

  test "rejects an invalid quality mode without creating an analyzer" do
    upload = Rack::Test::UploadedFile.new(StringIO.new("new-photo-bytes"), "image/jpeg", original_filename: "new-yard.jpg")
    analyzer_calls = 0
    analyzer_factory = lambda do |*|
      analyzer_calls += 1
      raise "analyzer must not run for an invalid quality mode"
    end

    Vision::SceneAnalyzer.stub(:for_quality, analyzer_factory) do
      post "/api/v1/scenes/analyze", params: { photo: upload, quality_mode: "ultra" }, headers: csrf_headers
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal 0, analyzer_calls
    assert_equal "invalid_request", body.fetch("error")
    assert_equal "$.quality_mode", body.fetch("errors").first.fetch("path")
  end

  test "downloads rbxlx" do
    post "/api/v1/scenes/export", params: { scene_spec: @spec }, headers: csrf_headers, as: :json

    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_match(/attachment/, response.headers.fetch("Content-Disposition"))
    assert_match(/<roblox/, response.body)
  end

  test "returns field-aware validation errors" do
    @spec.fetch("paths").first["surface_id"] = "unknown"
    post "/api/v1/scenes/compile", params: { scene_spec: @spec }, headers: csrf_headers, as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "$.paths[0].surface_id", body.fetch("errors").first.fetch("path")
  end

  test "rejects AI Lab access after sign out" do
    delete "/api/v1/auth/logout", headers: csrf_headers
    get "/api/v1/status"

    assert_response :unauthorized
  end

  private

  def csrf_headers
    { "X-CSRF-Token" => @csrf_token }
  end
end
