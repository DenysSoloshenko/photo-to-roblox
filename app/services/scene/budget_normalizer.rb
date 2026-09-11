module Scene
  class BudgetNormalizer
    def initialize(spec, budgets: Validator::DEFAULT_BUDGETS)
      @spec = deep_copy(spec)
      @budgets = budgets
    end

    def normalize
      original_estimated_parts = Validator.estimated_parts(@spec)
      part_budget = Validator.effective_part_budget(@budgets)
      original_group_instances = group_instances

      reduce_groups_to(part_budget) if original_estimated_parts > part_budget

      estimated_parts = Validator.estimated_parts(@spec)
      {
        scene_spec: @spec,
        metrics: {
          "budget_adjusted" => estimated_parts < original_estimated_parts,
          "original_estimated_parts" => original_estimated_parts,
          "estimated_parts" => estimated_parts,
          "removed_group_instances" => original_group_instances - group_instances
        }
      }
    end

    private

    def reduce_groups_to(part_budget)
      groups = @spec["groups"]
      return unless groups.is_a?(Array) && groups.all? { |group| group.is_a?(Hash) }

      group_parts = groups.sum { |group| group.fetch("count", 0).to_i * part_estimate(group) }
      base_parts = Validator.estimated_parts(@spec) - group_parts
      available_group_parts = part_budget - base_parts
      minimum_group_parts = groups.sum { |group| part_estimate(group) }
      return if group_parts.zero? || available_group_parts < minimum_group_parts

      scale = [available_group_parts.to_f / group_parts, 1.0].min
      groups.each do |group|
        group["count"] = [(group.fetch("count", 0).to_i * scale).floor, 1].max
      end

      while Validator.estimated_parts(@spec) > part_budget
        group = groups.select { |candidate| candidate.fetch("count", 0).to_i > 1 }
          .max_by { |candidate| candidate.fetch("count").to_i * part_estimate(candidate) }
        break unless group

        group["count"] -= 1
      end
    end

    def part_estimate(group)
      Validator::PART_ESTIMATES.fetch(group["object_type"], 1)
    end

    def group_instances
      Array(@spec["groups"]).sum { |group| group.is_a?(Hash) ? group.fetch("count", 0).to_i : 0 }
    end

    def deep_copy(value)
      Marshal.load(Marshal.dump(value))
    end
  end
end
