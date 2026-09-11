require "digest"

module Scene
  class Compiler
    COMPONENT_VERSION = "1.1.0"

    def initialize(registry: ComponentRegistry.default, budgets: Validator::DEFAULT_BUDGETS)
      @registry = registry
      @budgets = budgets
    end

    def compile_scene(spec, options = {})
      started_at = monotonic_time
      normalized = deep_stringify(spec)
      Validator.new(normalized, budgets: @budgets.merge(options.fetch(:budgets, {}))).validate!
      parts = []

      compile_surfaces(normalized, parts)
      compile_paths(normalized, parts)
      normalized.fetch("objects").each { |object| compile_object(normalized, parts, object) }
      compile_groups(normalized, parts)
      compile_spawn(normalized, parts)

      max_parts = @budgets.fetch("max_parts")
      if parts.length > max_parts
        raise BudgetError.new([{ path: "$", message: "compiled #{parts.length} parts exceeds budget #{max_parts}" }])
      end

      {
        "version" => "1.0",
        "component_version" => COMPONENT_VERSION,
        "name" => normalized.fetch("name"),
        "seed" => normalized.fetch("seed"),
        "spec_digest" => Digest::SHA256.hexdigest(canonical_json(normalized)),
        "bounds" => normalized.fetch("bounds"),
        "parts" => parts,
        "spawn" => normalized.fetch("spawn"),
        "camera" => normalized.fetch("camera"),
        "stats" => {
          "part_count" => parts.length,
          "triangle_estimate" => parts.sum { |part| part["shape"] == "block" ? 12 : 96 },
          "compile_ms" => ((monotonic_time - started_at) * 1000).round(2)
        }
      }
    end

    alias compile compile_scene

    private

    def compile_surfaces(spec, parts)
      spec.fetch("surfaces").each do |surface|
        material = surface.fetch("material")
        builder = builder_for(parts, spec, surface.fetch("id"))
        ellipse = surface.fetch("kind") == "ellipse"
        builder.part(
          name: surface.fetch("kind").capitalize,
          shape: ellipse ? "cylinder" : "block",
          position: [surface.dig("center", 0), surface.fetch("elevation") - surface.fetch("thickness") / 2.0, surface.dig("center", 2)],
          size: [surface.dig("size", 0), surface.fetch("thickness"), surface.dig("size", 1)],
          rotation: [0, surface.fetch("rotation_y"), 0],
          material: material,
          transparency: surface["kind"] == "water" ? 0.28 : 0.0,
          collidable: surface["kind"] != "water",
          cast_shadow: surface["kind"] != "water"
        )
      end
    end

    def compile_paths(spec, parts)
      spec.fetch("paths").each do |route|
        builder = builder_for(parts, spec, route.fetch("id"))
        route.fetch("points").each_cons(2).with_index do |(from, to), index|
          dx = to[0] - from[0]
          dy = to[1] - from[1]
          dz = to[2] - from[2]
          horizontal = Math.sqrt(dx * dx + dz * dz)
          length = Math.sqrt(dx * dx + dy * dy + dz * dz)
          yaw = Math.atan2(dx, dz) * 180.0 / Math::PI
          pitch = -Math.atan2(dy, [horizontal, 0.001].max) * 180.0 / Math::PI
          builder.part(
            name: "Path segment #{index + 1}", shape: "block",
            position: [(from[0] + to[0]) / 2.0, (from[1] + to[1]) / 2.0 - 0.02, (from[2] + to[2]) / 2.0],
            size: [route.fetch("width"), 0.25, length + 0.08], rotation: [pitch, yaw, 0],
            material: route.fetch("material"), collidable: true
          )
        end
        route.fetch("points").each_with_index do |point, index|
          builder.part(
            name: "Rounded path joint #{index + 1}", shape: "cylinder",
            position: [point[0], point[1] - 0.015, point[2]], size: [route.fetch("width"), 0.255, route.fetch("width")],
            material: route.fetch("material"), collidable: true
          )
        end
      end
    end

    def compile_groups(spec, parts)
      paths = spec.fetch("paths").to_h { |route| [route.fetch("id"), route] }
      spec.fetch("groups").each do |group|
        placements = placements_for(spec, group, paths)
        placements.each_with_index do |position, index|
          instance_id = "#{group.fetch("id")}-#{index + 1}"
          rng = Random.new(seed_for(spec, instance_id))
          scale = rng.rand(group.dig("scale_range", 0)..group.dig("scale_range", 1))
          object = {
            "id" => instance_id,
            "type" => group.fetch("object_type"),
            "position" => position,
            "rotation_y" => rng.rand(0.0..360.0),
            "scale" => [scale, scale, scale],
            "surface_id" => group["surface_id"],
            "params" => group.fetch("params")
          }
          compile_object(spec, parts, object)
        end
      end
    end

    def placements_for(spec, group, paths)
      count = group.fetch("count")
      center = group.fetch("area_center")
      size = group.fetch("area_size")
      rng = Random.new(seed_for(spec, group.fetch("id")))
      case group.fetch("distribution")
      when "grid"
        columns = Math.sqrt(count).ceil
        rows = (count.to_f / columns).ceil
        count.times.map do |index|
          column = index % columns
          row = index / columns
          x = center[0] + ((column + 0.5) / columns - 0.5) * size[0]
          z = center[2] + ((row + 0.5) / rows - 0.5) * size[1]
          [x, center[1], z]
        end
      when "along_path"
        route = paths.fetch(group.fetch("path_id"))
        count.times.map { |index| interpolate_path(route.fetch("points"), (index + 1.0) / (count + 1.0), rng.rand(-size[0] / 2.0..size[0] / 2.0)) }
      when "frame"
        inner_edge = size[0] * 0.22
        outer_edge = size[0] / 2.0
        count.times.map do |index|
          side = index.even? ? -1 : 1
          [center[0] + side * rng.rand(inner_edge..outer_edge), center[1], center[2] + rng.rand(-size[1] / 2.0..size[1] / 2.0)]
        end
      else
        count.times.map do
          [center[0] + rng.rand(-size[0] / 2.0..size[0] / 2.0), center[1], center[2] + rng.rand(-size[1] / 2.0..size[1] / 2.0)]
        end
      end
    end

    def interpolate_path(points, fraction, lateral_offset)
      segments = points.each_cons(2).map { |a, b| [a, b, Math.sqrt((b[0] - a[0])**2 + (b[2] - a[2])**2)] }
      total = segments.sum { |segment| segment[2] }
      target = total * fraction
      traversed = 0.0
      segment = segments.find { |entry| (traversed += entry[2]) >= target } || segments.last
      start, finish, length = segment
      before = traversed - length
      local = length.zero? ? 0.0 : (target - before) / length
      dx = finish[0] - start[0]
      dz = finish[2] - start[2]
      normal_x, normal_z = length.zero? ? [0, 0] : [dz / length, -dx / length]
      [
        start[0] + dx * local + normal_x * lateral_offset,
        start[1] + (finish[1] - start[1]) * local,
        start[2] + dz * local + normal_z * lateral_offset
      ]
    end

    def compile_object(spec, parts, object)
      @registry.compile(builder_for(parts, spec, object.fetch("id")), object)
    end

    def compile_spawn(spec, parts)
      spawn = spec.fetch("spawn")
      builder_for(parts, spec, "spawn").part(
        name: "Player spawn", shape: "block",
        position: [spawn.dig("position", 0), spawn.dig("position", 1) + 0.15, spawn.dig("position", 2)],
        size: [6, 0.3, 6], rotation: [0, spawn.fetch("rotation_y"), 0], material: "concrete",
        transparency: 1.0, collidable: true, cast_shadow: false
      )
      parts.last["class"] = "SpawnLocation"
    end

    def builder_for(parts, spec, source_id)
      PartBuilder.new(parts: parts, source_id: source_id, seed: seed_for(spec, source_id))
    end

    def seed_for(spec, semantic_id)
      Digest::SHA256.hexdigest("#{spec.fetch("seed")}:#{COMPONENT_VERSION}:#{semantic_id}")[0, 16].to_i(16) % 2_147_483_647
    end

    def deep_stringify(value)
      case value
      when Hash then value.to_h { |key, child| [key.to_s, deep_stringify(child)] }
      when Array then value.map { |child| deep_stringify(child) }
      else value
      end
    end

    def canonical_json(value)
      JSON.generate(sort_hashes(value))
    end

    def sort_hashes(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, sort_hashes(value[key])] }
      when Array then value.map { |item| sort_hashes(item) }
      else value
      end
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
