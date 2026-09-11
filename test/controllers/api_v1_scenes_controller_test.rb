require "test_helper"

class ApiV1ScenesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @spec = JSON.parse(Rails.root.join("examples/park.json").read)
  end

  test "compiles edited JSON" do
    post "/api/v1/scenes/compile", params: { scene_spec: @spec }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Riverside Park", body.dig("scene_ir", "name")
    assert body.dig("scene_ir", "stats", "part_count").positive?
  end

  test "serves a compiled development example" do
    get "/api/v1/scenes/examples/park"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @spec, body.fetch("scene_spec")
    assert_equal "Riverside Park", body.dig("scene_ir", "name")
  end

  test "takes a new upload through analysis and compilation without photo-specific code" do
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

    Vision::SceneAnalyzer.stub(:new, fake_analyzer) do
      post "/api/v1/scenes/analyze", params: { photo: upload, hint: "keep the large tree" }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Riverside Park", body.dig("scene_ir", "name")
    assert_equal "fake-vision", body.dig("metrics", "vision_model")
    assert_equal 0.0042, body.dig("metrics", "api_cost_usd")
    assert body.dig("metrics", "total_ms").positive?
    assert body.dig("metrics", "order_id").present?
  end

  test "normalizes an over-budget vision scene before compilation" do
    oversized = Marshal.load(Marshal.dump(@spec))
    oversized.fetch("groups").each { |group| group["count"] = 200 }
    fake_analyzer = Object.new
    fake_analyzer.define_singleton_method(:analyze) do |**|
      { scene_spec: oversized, metrics: { "vision_model" => "fake-vision", "vision_ms" => 50.0 } }
    end
    upload = Rack::Test::UploadedFile.new(StringIO.new("new-photo-bytes"), "image/jpeg", original_filename: "large-scene.jpg")

    Vision::SceneAnalyzer.stub(:new, fake_analyzer) do
      post "/api/v1/scenes/analyze", params: { photo: upload }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert body.dig("metrics", "budget_adjusted")
    assert_operator body.dig("metrics", "removed_group_instances"), :>, 0
    assert_operator body.dig("scene_ir", "stats", "part_count"), :<=, 1_500
  end

  test "downloads rbxlx" do
    post "/api/v1/scenes/export", params: { scene_spec: @spec }, as: :json

    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_match(/attachment/, response.headers.fetch("Content-Disposition"))
    assert_match(/<roblox/, response.body)
  end

  test "returns field-aware validation errors" do
    @spec.fetch("paths").first["surface_id"] = "unknown"
    post "/api/v1/scenes/compile", params: { scene_spec: @spec }, as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "$.paths[0].surface_id", body.fetch("errors").first.fetch("path")
  end
end
