require "test_helper"

class SceneGeometryNormalizerTest < ActiveSupport::TestCase
  test "scales oversized vision geometry into supported ranges" do
    source = JSON.parse(Rails.root.join("examples/park.json").read)
    source.fetch("bounds").merge!("width" => 1_000, "depth" => 800, "max_height" => 600)
    source.dig("objects", 0, "params")["height"] = 400
    source.dig("paths", 0)["width"] = 90
    source.dig("surfaces", 0)["thickness"] = 80
    source.dig("source")["scale_confidence"] = 1.4

    result = Scene::GeometryNormalizer.new(source).normalize
    normalized = result.fetch(:scene_spec)

    assert result.dig(:metrics, "geometry_adjusted")
    assert_equal 0.5, result.dig(:metrics, "geometry_scale")
    assert_equal 500, normalized.dig("bounds", "width")
    assert_equal 200, normalized.dig("objects", 0, "params", "height")
    assert_equal 30, normalized.dig("paths", 0, "width")
    assert_equal 20, normalized.dig("surfaces", 0, "thickness")
    assert_equal 1, normalized.dig("source", "scale_confidence")
    assert_equal 1_000, source.dig("bounds", "width")
    assert_equal normalized, Scene::Validator.new(normalized).validate!
  end

  test "leaves supported geometry at full scale" do
    source = JSON.parse(Rails.root.join("examples/park.json").read)

    result = Scene::GeometryNormalizer.new(source).normalize

    refute result.dig(:metrics, "geometry_adjusted")
    assert_equal 1.0, result.dig(:metrics, "geometry_scale")
    assert_equal source, result.fetch(:scene_spec)
  end
end
