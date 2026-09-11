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
      @spec.fetch("paths", []).each { |path| positions.concat(Array(path["points"])) if path.is_a?(Hash) }
      positions.select! { |position| position.is_a?(Array) && position.length == 3 && position.all? { |value| value.is_a?(Numeric) } }
      return false if positions.empty?

      required_width = positions.map { |position| position[0].abs * 2.0 }.max
      required_depth = positions.map { |position| position[2].abs * 2.0 }.max
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
      (@spec.fetch("objects", []) + @spec.fetch("groups", [])).filter_map do |item|
        next unless item.is_a?(Hash) && item["params"].is_a?(Hash)

        item["params"].values.select { |value| value.is_a?(Numeric) }.max
      end.max
    end

    def apply_scale(scale)
      bounds = @spec.fetch("bounds", {})
      %w[width depth max_height].each { |key| scale_number(bounds, key, scale) }

      @spec.fetch("surfaces", []).each do |surface|
        scale_vector(surface["center"], scale)
        scale_vector(surface["size"], scale)
        %w[elevation thickness].each { |key| scale_number(surface, key, scale) }
      end
      @spec.fetch("paths", []).each do |path|
        Array(path["points"]).each { |point| scale_vector(point, scale) }
        scale_number(path, "width", scale)
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
      end
      @spec.fetch("paths", []).each { |path| clamp_number(path, "width", 2, 30) }
      @spec.fetch("objects", []).each do |object|
        clamp_number(object, "rotation_y", -360, 360)
        clamp_params(object["params"])
      end
      @spec.fetch("groups", []).each do |group|
        clamp_number(group, "count", 1, 200)
        clamp_params(group["params"])
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
