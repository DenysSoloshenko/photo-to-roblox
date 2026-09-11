module Scene
  class Validator
    OBJECT_TYPES = %w[tree bush rock bench fence building].freeze
    GROUP_OBJECT_TYPES = %w[tree bush rock].freeze
    DISTRIBUTIONS = %w[scatter grid along_path].freeze
    PARAM_KEYS = %w[
      width depth height roof_height wall_thickness door_width door_height
      trunk_height trunk_diameter canopy_radius radius length post_spacing
      material roof_material roof_style
    ].freeze
    NUMERIC_PARAM_KEYS = PARAM_KEYS - %w[material roof_material roof_style]
    DEFAULT_BUDGETS = { "max_parts" => 1_500, "max_triangles" => 120_000 }.freeze
    PART_ESTIMATES = {
      "tree" => 5, "bush" => 4, "rock" => 1,
      "bench" => 7, "fence" => 32, "building" => 10
    }.freeze

    attr_reader :spec, :errors

    def initialize(spec, budgets: DEFAULT_BUDGETS)
      @spec = spec
      @budgets = DEFAULT_BUDGETS.merge(budgets || {})
      @errors = []
    end

    def validate!
      unless spec.is_a?(Hash)
        raise ValidationError.new([{ path: "$", message: "must be a JSON object" }])
      end

      exact("schema_version", "1.0")
      exact("units", "studs")
      error("$.axes.up", "must equal \"Y\"") unless spec.dig("axes", "up") == "Y"
      error("$.axes.forward", "must equal \"-Z\"") unless spec.dig("axes", "forward") == "-Z"
      require_string("name", max: 80)
      require_integer("seed", min: 0, max: 2_147_483_646)
      validate_bounds
      validate_source
      validate_collection_sizes
      validate_surfaces
      validate_paths
      validate_objects
      validate_groups
      validate_spawn_and_camera
      validate_global_ids
      validate_references
      validate_positions
      validate_spawn_safety
      validate_budget

      raise ValidationError.new(errors) if errors.any?

      spec
    end

    private

    def exact(key, expected)
      error("$.#{key}", "must equal #{expected.inspect}") unless spec[key] == expected
    end

    def require_string(key, max: nil)
      value = spec[key]
      error("$.#{key}", "must be a non-empty string") unless value.is_a?(String) && value.strip.length.positive?
      error("$.#{key}", "must be at most #{max} characters") if max && value.is_a?(String) && value.length > max
    end

    def require_integer(key, min:, max:)
      value = spec[key]
      return error("$.#{key}", "must be an integer") unless value.is_a?(Integer)

      error("$.#{key}", "must be between #{min} and #{max}") unless value.between?(min, max)
    end

    def validate_bounds
      bounds = spec["bounds"]
      unless bounds.is_a?(Hash)
        error("$.bounds", "must be an object")
        return
      end

      %w[width depth max_height].each do |key|
        number(bounds[key], "$.bounds.#{key}", min: key == "max_height" ? 5 : 20, max: 500)
      end
    end

    def validate_source
      source = spec["source"]
      return error("$.source", "must be an object") unless source.is_a?(Hash)

      summary = source["summary"]
      error("$.source.summary", "must be a string of at most 500 characters") unless summary.is_a?(String) && summary.length <= 500
      number(source["scale_confidence"], "$.source.scale_confidence", min: 0, max: 1)
      assumptions = source["assumptions"]
      unless assumptions.is_a?(Array)
        error("$.source.assumptions", "must be an array")
        return
      end
      error("$.source.assumptions", "must contain at most 10 items") if assumptions.length > 10
      assumptions.each_with_index do |assumption, index|
        error("$.source.assumptions[#{index}]", "must be a string of at most 180 characters") unless assumption.is_a?(String) && assumption.length <= 180
      end
    end

    def validate_collection_sizes
      { "surfaces" => 30, "paths" => 20, "objects" => 100, "groups" => 30 }.each do |key, max|
        values = collection(key)
        error("$.#{key}", "must contain at most #{max} items") if values.length > max
      end
    end

    def validate_surfaces
      collection("surfaces").each_with_index do |surface, index|
        path = "$.surfaces[#{index}]"
        next error(path, "must be an object") unless surface.is_a?(Hash)

        id(surface, path)
        enum(surface["kind"], %w[ground platform water], "#{path}.kind")
        vector(surface["center"], 3, "#{path}.center")
        vector(surface["size"], 2, "#{path}.size", positive: true)
        number(surface["elevation"], "#{path}.elevation", min: -50, max: 150)
        number(surface["thickness"], "#{path}.thickness", min: 0.05, max: 20)
        number(surface["rotation_y"], "#{path}.rotation_y", min: -360, max: 360)
        material(surface["material"], "#{path}.material")
      end
      error("$.surfaces", "must contain at least one ground surface") unless collection("surfaces").any? { |surface| surface.is_a?(Hash) && surface["kind"] == "ground" }
    end

    def validate_paths
      collection("paths").each_with_index do |route, index|
        path = "$.paths[#{index}]"
        next error(path, "must be an object") unless route.is_a?(Hash)

        id(route, path)
        points = route["points"]
        if !points.is_a?(Array) || points.length < 2
          error("#{path}.points", "must contain at least two [x,y,z] points", id: route["id"])
        else
          points.each_with_index { |point, point_index| vector(point, 3, "#{path}.points[#{point_index}]") }
        end
        number(route["width"], "#{path}.width", min: 2, max: 30)
        material(route["material"], "#{path}.material")
        optional_string(route["surface_id"], "#{path}.surface_id")
      end
    end

    def validate_objects
      collection("objects").each_with_index do |object, index|
        path = "$.objects[#{index}]"
        next error(path, "must be an object") unless object.is_a?(Hash)

        id(object, path)
        enum(object["type"], OBJECT_TYPES, "#{path}.type", id: object["id"])
        vector(object["position"], 3, "#{path}.position")
        number(object["rotation_y"], "#{path}.rotation_y", min: -360, max: 360)
        vector(object["scale"], 3, "#{path}.scale", positive: true)
        optional_string(object["surface_id"], "#{path}.surface_id")
        validate_params(object["params"], "#{path}.params", object["id"])
      end
    end

    def validate_groups
      collection("groups").each_with_index do |group, index|
        path = "$.groups[#{index}]"
        next error(path, "must be an object") unless group.is_a?(Hash)

        id(group, path)
        enum(group["object_type"], GROUP_OBJECT_TYPES, "#{path}.object_type", id: group["id"])
        enum(group["distribution"], DISTRIBUTIONS, "#{path}.distribution", id: group["id"])
        integer(group["count"], "#{path}.count", min: 1, max: 200)
        vector(group["area_center"], 3, "#{path}.area_center")
        vector(group["area_size"], 2, "#{path}.area_size", positive: true)
        vector(group["scale_range"], 2, "#{path}.scale_range", positive: true)
        optional_string(group["surface_id"], "#{path}.surface_id")
        optional_string(group["path_id"], "#{path}.path_id")
        validate_params(group["params"], "#{path}.params", group["id"])
      end
    end

    def validate_spawn_and_camera
      spawn = spec["spawn"]
      if spawn.is_a?(Hash)
        vector(spawn["position"], 3, "$.spawn.position")
        number(spawn["rotation_y"], "$.spawn.rotation_y", min: -360, max: 360)
      else
        error("$.spawn", "must be an object")
      end

      camera = spec["camera"]
      if camera.is_a?(Hash)
        vector(camera["position"], 3, "$.camera.position")
        vector(camera["target"], 3, "$.camera.target")
        number(camera["fov"], "$.camera.fov", min: 25, max: 90)
      else
        error("$.camera", "must be an object")
      end
    end

    def validate_global_ids
      entries = %w[surfaces paths objects groups].flat_map do |key|
        collection(key).filter_map.with_index { |item, index| [item["id"], "$.#{key}[#{index}].id"] if item.is_a?(Hash) }
      end
      entries.group_by(&:first).each do |value, matches|
        next if value.nil? || matches.length == 1

        matches.each { |(_, path)| error(path, "duplicate semantic ID #{value.inspect}", id: value) }
      end
    end

    def validate_references
      surface_ids = collection("surfaces").filter_map { |item| item["id"] if item.is_a?(Hash) }
      path_ids = collection("paths").filter_map { |item| item["id"] if item.is_a?(Hash) }

      collection("paths").each_with_index do |route, index|
        validate_reference(route, "surface_id", surface_ids, "$.paths[#{index}]", route["id"]) if route.is_a?(Hash)
      end
      collection("objects").each_with_index do |object, index|
        validate_reference(object, "surface_id", surface_ids, "$.objects[#{index}]", object["id"]) if object.is_a?(Hash)
      end
      collection("groups").each_with_index do |group, index|
        next unless group.is_a?(Hash)

        validate_reference(group, "surface_id", surface_ids, "$.groups[#{index}]", group["id"])
        validate_reference(group, "path_id", path_ids, "$.groups[#{index}]", group["id"])
        if group["distribution"] == "along_path" && group["path_id"].to_s.empty?
          error("$.groups[#{index}].path_id", "is required for along_path", id: group["id"])
        end
      end
    end

    def validate_positions
      return unless spec["bounds"].is_a?(Hash)

      half_width = spec["bounds"]["width"].to_f / 2.0
      half_depth = spec["bounds"]["depth"].to_f / 2.0
      checks = [[spec.dig("spawn", "position"), "$.spawn.position", "spawn"]]
      collection("objects").each_with_index { |object, index| checks << [object["position"], "$.objects[#{index}].position", object["id"]] if object.is_a?(Hash) }
      collection("paths").each_with_index do |route, index|
        Array(route["points"]).each_with_index { |point, point_index| checks << [point, "$.paths[#{index}].points[#{point_index}]", route["id"]] } if route.is_a?(Hash)
      end
      checks.each do |position, path, semantic_id|
        next unless position.is_a?(Array) && position.length == 3 && position.all? { |item| item.is_a?(Numeric) }

        error(path, "lies outside scene bounds", id: semantic_id) if position[0].abs > half_width || position[2].abs > half_depth
      end
    end

    def validate_spawn_safety
      position = spec.dig("spawn", "position")
      return unless position.is_a?(Array) && position.length == 3

      collection("surfaces").each_with_index do |surface, index|
        next unless surface.is_a?(Hash) && surface["kind"] == "water" && inside_rectangle?(position, surface["center"], surface["size"])

        error("$.spawn.position", "must not be inside water surface #{surface["id"]}", id: surface["id"])
      end
      collection("objects").each_with_index do |object, index|
        next unless object.is_a?(Hash) && object["type"] == "building"

        params = object["params"] || {}
        size = [params.fetch("width", 16).to_f, params.fetch("depth", 12).to_f]
        if inside_rectangle?(position, object["position"], size)
          error("$.spawn.position", "must not be inside building #{object["id"]}", id: object["id"])
        end
      end
    end

    def validate_budget
      surface_parts = collection("surfaces").length
      path_parts = collection("paths").sum { |route| [Array(route["points"]).length - 1, 0].max }
      object_parts = collection("objects").sum { |object| PART_ESTIMATES.fetch(object["type"], 1) }
      group_parts = collection("groups").sum { |group| group.fetch("count", 0).to_i * PART_ESTIMATES.fetch(group["object_type"], 1) }
      estimated_parts = surface_parts + path_parts + object_parts + group_parts + 1
      estimated_triangles = estimated_parts * 96
      if estimated_parts > @budgets["max_parts"].to_i
        raise BudgetError.new([{ path: "$.groups", message: "estimated #{estimated_parts} parts exceeds budget #{@budgets["max_parts"]}" }])
      end
      if estimated_triangles > @budgets["max_triangles"].to_i
        raise BudgetError.new([{ path: "$.groups", message: "estimated #{estimated_triangles} triangles exceeds budget #{@budgets["max_triangles"]}" }])
      end
    end

    def collection(key)
      value = spec[key]
      unless value.is_a?(Array)
        error("$.#{key}", "must be an array") unless errors.any? { |item| item[:path] == "$.#{key}" && item[:message] == "must be an array" }
        return []
      end
      value
    end

    def validate_params(params, path, semantic_id)
      return error(path, "must be an object", id: semantic_id) unless params.is_a?(Hash)

      (PARAM_KEYS - params.keys).each { |key| error("#{path}.#{key}", "is required", id: semantic_id) }
      (params.keys - PARAM_KEYS).each { |key| error("#{path}.#{key}", "is not supported", id: semantic_id) }
      NUMERIC_PARAM_KEYS.each do |key|
        value = params[key]
        number(value, "#{path}.#{key}", min: 0.01, max: 200) unless value.nil?
      end
      %w[material roof_material].each do |key|
        value = params[key]
        material(value, "#{path}.#{key}") unless value.nil?
      end
      enum(params["roof_style"], ["gable", "flat", nil], "#{path}.roof_style", id: semantic_id)
    end

    def id(value, path)
      id = value["id"]
      error("#{path}.id", "must match [a-z][a-z0-9_-]*") unless id.is_a?(String) && id.match?(/\A[a-z][a-z0-9_-]*\z/)
    end

    def material(value, path)
      enum(value, MaterialCatalog.names, path)
    end

    def vector(value, length, path, positive: false)
      unless value.is_a?(Array) && value.length == length && value.all? { |item| item.is_a?(Numeric) && item.finite? }
        error(path, "must be an array of #{length} finite numbers")
        return
      end
      error(path, "values must be positive") if positive && value.any? { |item| item <= 0 }
    end

    def number(value, path, min:, max:)
      return error(path, "must be a finite number") unless value.is_a?(Numeric) && value.finite?

      error(path, "must be between #{min} and #{max}") unless value.between?(min, max)
    end

    def integer(value, path, min:, max:)
      return error(path, "must be an integer") unless value.is_a?(Integer)

      error(path, "must be between #{min} and #{max}") unless value.between?(min, max)
    end

    def enum(value, values, path, id: nil)
      error(path, "must be one of #{values.join(", ")}", id: id) unless values.include?(value)
    end

    def optional_string(value, path)
      error(path, "must be a string or null") unless value.nil? || value.is_a?(String)
    end

    def validate_reference(item, key, allowed, path, semantic_id)
      value = item[key]
      return if value.nil? || value == ""

      error("#{path}.#{key}", "references unknown ID #{value.inspect}", id: semantic_id) unless allowed.include?(value)
    end

    def inside_rectangle?(position, center, size)
      return false unless center.is_a?(Array) && size.is_a?(Array)

      (position[0] - center[0]).abs <= size[0] / 2.0 && (position[2] - center[2]).abs <= size[1] / 2.0
    end

    def error(path, message, id: nil)
      errors << { path: path, message: message, id: id }.compact
    end
  end
end
