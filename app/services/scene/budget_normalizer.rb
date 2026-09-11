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
      reduce_patterns_to(part_budget) if Validator.estimated_parts(@spec) > part_budget

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

    def reduce_patterns_to(part_budget)
      patterns = Array(@spec["patterns"])
      100.times do
        break if Validator.estimated_parts(@spec) <= part_budget

        candidate = patterns.max_by { |pattern| Validator.pattern_estimated_parts(pattern) }
        break unless candidate

        changed = case candidate["type"]
        when "formal_garden"
          if candidate.fetch("ring_count", 0).to_i.positive?
            candidate["ring_count"] -= 1
            true
          elsif candidate.fetch("flower_density", 0).to_f > 0.2
            candidate["flower_density"] = [candidate["flower_density"].to_f * 0.85, 0.2].max.round(3)
            true
          elsif candidate.fetch("petal_count", 0).to_i > 3
            candidate["petal_count"] -= 1
            true
          else
            false
          end
        when "forest_frame"
          if candidate.fetch("count", 0).to_i > 4
            candidate["count"] -= 1
            true
          else
            false
          end
        when "mountain_ridge"
          if candidate.fetch("peak_count", 0).to_i > 3
            candidate["peak_count"] -= 1
            true
          else
            false
          end
        else
          false
        end
        break unless changed
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
