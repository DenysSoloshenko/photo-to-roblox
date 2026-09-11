require "test_helper"

class SceneCompilerTest < ActiveSupport::TestCase
  def setup
    @compiler = Scene::Compiler.new
    @park = JSON.parse(Rails.root.join("examples/park.json").read)
  end

  test "all development examples compile with one core" do
    Dir[Rails.root.join("examples/*.json")].sort.each do |path|
      scene = @compiler.compile_scene(JSON.parse(File.read(path)))
      assert scene.dig("stats", "part_count").positive?, path
      assert_operator scene.dig("stats", "part_count"), :<=, 1_500
      assert_equal 1, scene.fetch("parts").count { |part| part["class"] == "SpawnLocation" }
    end
  end

  test "same spec is deterministic" do
    first = @compiler.compile_scene(@park)
    second = @compiler.compile_scene(@park)

    assert_equal first.fetch("spec_digest"), second.fetch("spec_digest")
    assert_equal first.fetch("parts"), second.fetch("parts")
  end

  test "compiles expressive garden geometry with color and curved forms" do
    garden = Marshal.load(Marshal.dump(@park))
    blank_params = garden.dig("objects", 0, "params").transform_values { nil }
    garden.fetch("surfaces") << {
      "id" => "round_bed", "kind" => "ellipse", "center" => [0, 0.5, 4], "size" => [18, 12],
      "elevation" => 0.5, "thickness" => 1, "rotation_y" => 0, "material" => "earth"
    }
    garden.fetch("objects") << {
      "id" => "rose_arch", "type" => "arch", "position" => [0, 0, 2], "rotation_y" => 0,
      "scale" => [1, 1, 1], "surface_id" => "main_lawn",
      "params" => blank_params.merge("width" => 10, "depth" => 4, "height" => 14, "material" => "metal", "roof_material" => "stone")
    }
    garden.fetch("objects") << {
      "id" => "distant_peak", "type" => "mountain", "position" => [0, 0, -36], "rotation_y" => 0,
      "scale" => [1, 1, 1], "surface_id" => "main_lawn",
      "params" => blank_params.merge("width" => 24, "depth" => 10, "height" => 12, "material" => "mountain")
    }
    garden.fetch("groups") << {
      "id" => "red_roses", "object_type" => "flower", "distribution" => "grid", "count" => 4,
      "area_center" => [0, 0.5, 4], "area_size" => [10, 6], "scale_range" => [0.9, 1.1],
      "surface_id" => "round_bed", "path_id" => nil,
      "params" => blank_params.merge("height" => 2.2, "radius" => 0.6, "material" => "flower_red")
    }
    garden.fetch("groups") << {
      "id" => "clipped_border", "object_type" => "hedge", "distribution" => "grid", "count" => 4,
      "area_center" => [0, 0.5, 10], "area_size" => [16, 1], "scale_range" => [0.95, 1.05],
      "surface_id" => "main_lawn", "path_id" => nil,
      "params" => blank_params.merge("width" => 4, "depth" => 1.2, "height" => 1.5, "material" => "evergreen")
    }
    garden.fetch("groups") << {
      "id" => "vista_conifers", "object_type" => "conifer", "distribution" => "frame", "count" => 4,
      "area_center" => [0, 0, -30], "area_size" => [40, 8], "scale_range" => [0.9, 1.1],
      "surface_id" => "main_lawn", "path_id" => nil,
      "params" => blank_params.merge("trunk_height" => 12, "trunk_diameter" => 1.2, "canopy_radius" => 4, "material" => "evergreen")
    }

    scene = @compiler.compile_scene(garden)

    assert_equal "cylinder", scene.fetch("parts").find { |part| part["source_id"] == "round_bed" }.fetch("shape")
    assert_equal 9, scene.fetch("parts").count { |part| part["source_id"] == "main_walk" }
    assert_equal 20, scene.fetch("parts").count { |part| part["source_id"].start_with?("red_roses-") }
    assert scene.fetch("parts").any? { |part| part["source_id"].start_with?("red_roses-") && part["material"] == "flower_red" }
    assert_equal 27, scene.fetch("parts").count { |part| part["source_id"] == "rose_arch" }
    assert_equal 3, scene.fetch("parts").count { |part| part["source_id"] == "distant_peak" }
    assert_equal 4, scene.fetch("parts").count { |part| part["source_id"].start_with?("clipped_border-") }
    conifer_trunks = scene.fetch("parts").select { |part| part["source_id"].start_with?("vista_conifers-") && part["name"] == "Trunk" }
    assert_equal 4, conifer_trunks.length
    assert conifer_trunks.all? { |part| part.dig("position", 0).abs >= 8.8 }
  end

  test "invalid reference reports exact path and semantic id" do
    @park.fetch("objects").first["surface_id"] = "missing_surface"
    error = assert_raises(Scene::ValidationError) { @compiler.compile_scene(@park) }

    assert_includes error.errors, {
      path: "$.objects[0].surface_id",
      message: "references unknown ID \"missing_surface\"",
      id: "oak_west"
    }
  end

  test "budget is checked before expansion" do
    compiler = Scene::Compiler.new(budgets: { "max_parts" => 20, "max_triangles" => 10_000 })
    error = assert_raises(Scene::BudgetError) { compiler.compile_scene(@park) }

    assert_match(/exceeds budget 20/, error.message)
  end

  test "changing one object does not randomize another component" do
    baseline = @compiler.compile_scene(@park)
    changed = Marshal.load(Marshal.dump(@park))
    changed.fetch("objects").first.fetch("params")["trunk_height"] = 10
    rebuilt = @compiler.compile_scene(changed)

    baseline_other = baseline.fetch("parts").select { |part| part["source_id"] == "oak_center" }
    rebuilt_other = rebuilt.fetch("parts").select { |part| part["source_id"] == "oak_center" }
    refute_equal baseline.fetch("parts").select { |part| part["source_id"] == "oak_west" }, rebuilt.fetch("parts").select { |part| part["source_id"] == "oak_west" }
    assert_equal baseline_other, rebuilt_other
  end

  test "rejects unsupported repeated components before expansion" do
    @park.fetch("groups").first["object_type"] = "building"
    error = assert_raises(Scene::ValidationError) { @compiler.compile_scene(@park) }

    assert_includes error.errors, {
      path: "$.groups[0].object_type",
      message: "must be one of #{Scene::Validator::GROUP_OBJECT_TYPES.join(', ')}",
      id: "north_trees"
    }
  end

  test "rejects invalid component parameters with a field-aware error" do
    @park.fetch("objects").first.fetch("params")["material"] = "brick_texture"
    error = assert_raises(Scene::ValidationError) { @compiler.compile_scene(@park) }

    assert_includes error.errors, {
      path: "$.objects[0].params.material",
      message: "must be one of #{Scene::MaterialCatalog.names.join(", ")}"
    }
  end
end
