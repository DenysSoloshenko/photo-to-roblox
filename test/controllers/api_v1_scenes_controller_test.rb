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
