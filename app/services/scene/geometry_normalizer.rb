module Scene
  class GeometryNormalizer
    def initialize(spec)
      @spec = deep_copy(spec)
    end

    def normalize
      original = Marshal.dump(@spec)
      bounds_expanded = expand_bounds_to_references
      scale = required_scale
      apply_scale(scale) if scale < 1.0
      clamp_ranges

      {
        scene_spec: @spec,
        metrics: {
          "geometry_adjusted" => Marshal.dump(@spec) != original,
          "geometry_scale" => scale.round(6),
          "bounds_expanded" => bounds_expanded
        }
      }
    end

    private

    def expand_bounds_to_references
      bounds = @spec.fetch("bounds", {})
      positions = []
      positions << @spec.dig("spawn", "position")
      positions.concat(@spec.fetch("objects", []).filter_map { |object| object["position"] if object.is_a?(Hash) })
      positions.concat(@spec.fetch("groups", []).filter_map { |group| group["area_center"] if group.is_a?(Hash) })
      positions.concat(@spec.fetch("patterns", []).filter_map { |pattern| pattern["center"] if pattern.is_a?(Hash) })
      @spec.fetch("paths", []).each { |path| positions.concat(Array(path["points"])) if path.is_a?(Hash) }
      @spec.fetch("surfaces", []).each { |surface| positions.concat(Array(surface["points"])) if surface.is_a?(Hash) }
      positions.select! { |position| position.is_a?(Array) && position.length == 3 && position.all? { |value| value.is_a?(Numeric) } }
      return false if positions.empty?

      required_width = positions.map { |position| position[0].abs * 2.0 }.max
      required_depth = positions.map { |position| position[2].abs * 2.0 }.max
      @spec.fetch("patterns", []).each do |pattern|
        next unless pattern.is_a?(Hash) && pattern["center"].is_a?(Array)

        required_width = [required_width, (pattern["center"][0].abs + pattern.fetch("width", 0).to_f / 2.0) * 2.0].max
        required_depth = [required_depth, (pattern["center"][2].abs + pattern.fetch("depth", 0).to_f / 2.0) * 2.0].max
      end
      original_width = bounds["width"]
      original_depth = bounds["depth"]
      bounds["width"] = required_width if original_width.is_a?(Numeric) && required_width > original_width
      bounds["depth"] = required_depth if original_depth.is_a?(Numeric) && required_depth > original_depth
      bounds["width"] != original_width || bounds["depth"] != original_depth
    end

    def required_scale
      bounds = @spec.fetch("bounds", {})
      limits = [
        ratio(500, bounds["width"]),
        ratio(500, bounds["depth"]),
        ratio(500, bounds["max_height"]),
        ratio(200, largest_component_dimension)
      ]
      ([1.0] + limits.compact).min
    end

    def ratio(limit, value)
      return unless value.is_a?(Numeric) && value.positive?

      limit.to_f / value
    end

    def largest_component_dimension
      component_max = (@spec.fetch("objects", []) + @spec.fetch("groups", [])).filter_map do |item|
        next unless item.is_a?(Hash) && item["params"].is_a?(Hash)

        item["params"].values.select { |value| value.is_a?(Numeric) }.max
      end.max
      pattern_max = @spec.fetch("patterns", []).filter_map do |pattern|
        pattern.values.select { |value| value.is_a?(Numeric) }.max if pattern.is_a?(Hash)
      end.max
      [component_max, pattern_max].compact.max
    end

    def apply_scale(scale)
      bounds = @spec.fetch("bounds", {})
      %w[width depth max_height].each { |key| scale_number(bounds, key, scale) }

      @spec.fetch("surfaces", []).each do |surface|
        scale_vector(surface["center"], scale)
        scale_vector(surface["size"], scale)
        Array(surface["points"]).each { |point| scale_vector(point, scale) }
        %w[elevation thickness border_width border_height].each { |key| scale_number(surface, key, scale) }
      end
      @spec.fetch("paths", []).each do |path|
        Array(path["points"]).each { |point| scale_vector(point, scale) }
        %w[width border_width border_height].each { |key| scale_number(path, key, scale) }
      end
      @spec.fetch("objects", []).each do |object|
        scale_vector(object["position"], scale)
        scale_params(object["params"], scale)
      end
      @spec.fetch("groups", []).each do |group|
        scale_vector(group["area_center"], scale)
        scale_vector(group["area_size"], scale)
        scale_params(group["params"], scale)
      end
      @spec.fetch("patterns", []).each do |pattern|
        scale_vector(pattern["center"], scale)
        %w[width depth height center_radius path_width bed_height border_width border_height rise min_height max_height].each do |key|
          scale_number(pattern, key, scale)
        end
      end
      scale_vector(@spec.dig("spawn", "position"), scale)
      scale_vector(@spec.dig("camera", "position"), scale)
      scale_vector(@spec.dig("camera", "target"), scale)
    end

    def clamp_ranges
      bounds = @spec.fetch("bounds", {})
      clamp_number(bounds, "width", 20, 500)
      clamp_number(bounds, "depth", 20, 500)
      clamp_number(bounds, "max_height", 5, 500)
      clamp_number(@spec.fetch("source", {}), "scale_confidence", 0, 1)

      @spec.fetch("surfaces", []).each do |surface|
        clamp_number(surface, "elevation", -50, 150)
        clamp_number(surface, "thickness", 0.05, 20)
        clamp_number(surface, "rotation_y", -360, 360)
        clamp_number(surface, "border_width", 0.05, 5)
        clamp_number(surface, "border_height", 0.05, 5)
      end
      @spec.fetch("paths", []).each do |path|
        clamp_number(path, "width", 2, 30)
        clamp_number(path, "border_width", 0.05, 5)
        clamp_number(path, "border_height", 0.05, 5)
      end
      @spec.fetch("objects", []).each do |object|
        clamp_number(object, "rotation_y", -360, 360)
        clamp_params(object["params"])
      end
      @spec.fetch("groups", []).each do |group|
        clamp_number(group, "count", 1, 200)
        clamp_params(group["params"])
      end
      @spec.fetch("patterns", []).each do |pattern|
        clamp_number(pattern, "rotation_y", -360, 360)
        case pattern["type"]
        when "formal_garden"
          %w[width depth].each { |key| clamp_number(pattern, key, 8, 200) }
          clamp_number(pattern, "petal_count", 3, 10)
          clamp_number(pattern, "ring_count", 0, 3)
          %w[center_radius path_width].each { |key| clamp_number(pattern, key, 1, 30) }
          %w[bed_height border_width border_height].each { |key| clamp_number(pattern, key, 0.05, 5) }
          clamp_number(pattern, "flower_density", 0.1, 1)
        when "terrace"
          %w[width depth].each { |key| clamp_number(pattern, key, 8, 200) }
          clamp_number(pattern, "levels", 2, 8)
          clamp_number(pattern, "rise", 0.25, 10)
        when "mountain_ridge"
          %w[width depth height].each { |key| clamp_number(pattern, key, 3, 200) }
          clamp_number(pattern, "peak_count", 3, 12)
        when "forest_frame"
          %w[width depth].each { |key| clamp_number(pattern, key, 8, 200) }
          clamp_number(pattern, "count", 4, 40)
          %w[min_height max_height].each { |key| clamp_number(pattern, key, 3, 80) }
          clamp_number(pattern, "evergreen_ratio", 0, 1)
        end
      end
      clamp_number(@spec.fetch("spawn", {}), "rotation_y", -360, 360)
      clamp_number(@spec.fetch("camera", {}), "fov", 25, 90)
      clamp_number(@spec, "seed", 0, 2_147_483_646)
    end

    def scale_params(params, scale)
      return unless params.is_a?(Hash)

      Validator::NUMERIC_PARAM_KEYS.each { |key| scale_number(params, key, scale) }
    end

    def clamp_params(params)
      return unless params.is_a?(Hash)

      Validator::NUMERIC_PARAM_KEYS.each { |key| clamp_number(params, key, 0.01, 200) }
    end

    def scale_vector(vector, scale)
      return unless vector.is_a?(Array)

      vector.map! { |value| value.is_a?(Numeric) ? value * scale : value }
    end

    def scale_number(hash, key, scale)
      value = hash[key]
      hash[key] = value * scale if value.is_a?(Numeric)
    end

    def clamp_number(hash, key, minimum, maximum)
      value = hash[key]
      hash[key] = value.clamp(minimum, maximum) if value.is_a?(Numeric)
    end

    def deep_copy(value)
      Marshal.load(Marshal.dump(value))
    end
  end
end
