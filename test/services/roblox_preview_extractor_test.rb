require "test_helper"

class RobloxPreviewExtractorTest < ActiveSupport::TestCase
  test "extracts a browser preview from an rbxlx map" do
    scene = Roblox::PreviewExtractor.new.extract(file_fixture("result.rbxlx").read)

    assert_equal "Customer garden", scene.fetch("name")
    assert_equal 1, scene.dig("stats", "part_count")
    assert_equal "block", scene.dig("parts", 0, "shape")
    assert_equal [8.0, 0.5, 20.0], scene.dig("parts", 0, "size")
    assert_equal [24.0, 18.0, 30.0], scene.dig("camera", "position")
  end
end
