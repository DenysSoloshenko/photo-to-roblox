require "test_helper"

class SceneBudgetNormalizerTest < ActiveSupport::TestCase
  test "reduces repeated groups proportionally without changing the source spec" do
    source = JSON.parse(Rails.root.join("examples/park.json").read)
    source.fetch("groups").each { |group| group["count"] = 200 }

    result = Scene::BudgetNormalizer.new(source).normalize
    normalized = result.fetch(:scene_spec)
    metrics = result.fetch(:metrics)

    assert metrics.fetch("budget_adjusted")
    assert_operator metrics.fetch("removed_group_instances"), :>, 0
    assert_operator Scene::Validator.estimated_parts(normalized), :<=, Scene::Validator.effective_part_budget
    assert normalized.fetch("groups").all? { |group| group.fetch("count") >= 1 }
    assert_equal 200, source.dig("groups", 0, "count")
    assert_equal source.fetch("objects"), normalized.fetch("objects")
    assert_equal normalized, Scene::Validator.new(normalized).validate!
  end

  test "leaves an in-budget scene unchanged" do
    source = JSON.parse(Rails.root.join("examples/park.json").read)

    result = Scene::BudgetNormalizer.new(source).normalize

    refute result.dig(:metrics, "budget_adjusted")
    assert_equal source, result.fetch(:scene_spec)
    assert_equal 0, result.dig(:metrics, "removed_group_instances")
  end
end
