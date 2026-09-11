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
      message: "must be one of tree, bush, rock",
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
