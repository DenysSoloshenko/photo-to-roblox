require "digest"

module Scene
  class Compiler
    COMPONENT_VERSION = "1.2.0"

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
      compile_patterns(normalized, parts)
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
        builder = builder_for(parts, spec, surface.fetch("id"))
        if surface.fetch("kind") == "polygon"
          compile_polygon_surface(builder, surface)
        else
          ellipse = surface.fetch("kind") == "ellipse"
          builder.part(
            name: surface.fetch("kind").capitalize,
            shape: ellipse ? "cylinder" : "block",
            position: [surface.dig("center", 0), surface.fetch("elevation") - surface.fetch("thickness") / 2.0, surface.dig("center", 2)],
            size: [surface.dig("size", 0), surface.fetch("thickness"), surface.dig("size", 1)],
            rotation: [0, surface.fetch("rotation_y"), 0],
            material: surface.fetch("material"),
            transparency: surface["kind"] == "water" ? 0.28 : 0.0,
            collidable: surface["kind"] != "water",
            cast_shadow: surface["kind"] != "water"
          )
        end
        compile_surface_border(builder, surface)
      end
    end

    def compile_paths(spec, parts)
      spec.fetch("paths").each do |route|
        builder = builder_for(parts, spec, route.fetch("id"))
        points = route.fetch("curve") ? catmull_rom(route.fetch("points"), subdivisions: 3) : route.fetch("points")
        points.each_cons(2).with_index do |(from, to), index|
          segment_part(
            builder, from, to, width: route.fetch("width"), height: 0.25,
            material: route.fetch("material"), name: "Path segment #{index + 1}", vertical_offset: -0.02
          )
        end
        points.each_with_index do |point, index|
          builder.part(
            name: "Rounded path joint #{index + 1}", shape: "cylinder",
            position: [point[0], point[1] - 0.015, point[2]], size: [route.fetch("width"), 0.255, route.fetch("width")],
            material: route.fetch("material"), collidable: true
          )
        end
        compile_path_borders(builder, route, points)
      end
    end

    def compile_patterns(spec, parts)
      spec.fetch("patterns").each do |pattern|
        builder = builder_for(parts, spec, pattern.fetch("id"))
        case pattern.fetch("type")
        when "formal_garden" then compile_formal_garden(builder, pattern)
        when "terrace" then compile_terrace(builder, pattern)
        when "mountain_ridge" then compile_mountain_ridge(builder, pattern)
        when "forest_frame" then compile_forest_frame(builder, pattern)
        end
      end
    end

    def compile_polygon_surface(builder, surface)
      points = surface.fetch("points")
      minimum_z, maximum_z = points.map { |point| point[2] }.minmax
      strip_count = [[((maximum_z - minimum_z) / 2.5).ceil, 8].max, 24].min
      strip_depth = (maximum_z - minimum_z) / strip_count
      strip_count.times do |index|
        z = minimum_z + (index + 0.5) * strip_depth
        scanline_intersections(points, z).each_slice(2).with_index do |(left, right), span_index|
          next unless right && right > left

          builder.part(
            name: "Polygon fill #{index + 1}.#{span_index + 1}", shape: "block",
            position: [(left + right) / 2.0, surface.fetch("elevation") - surface.fetch("thickness") / 2.0, z],
            size: [right - left + 0.04, surface.fetch("thickness"), strip_depth + 0.04],
            material: surface.fetch("material"),
            transparency: surface["material"] == "water" ? 0.28 : 0.0,
            collidable: surface["material"] != "water",
            cast_shadow: surface["material"] != "water"
          )
        end
      end
    end

    def scanline_intersections(points, z)
      points.each_with_index.filter_map do |point, index|
        following = points[(index + 1) % points.length]
        z1, z2 = point[2], following[2]
        next unless (z1 <= z && z2 > z) || (z2 <= z && z1 > z)

        point[0] + (z - z1) * (following[0] - point[0]) / (z2 - z1)
      end.sort
    end

    def compile_surface_border(builder, surface)
      width = surface["border_width"]
      height = surface["border_height"]
      material = surface["border_material"]
      return unless width && height && material

      points = case surface.fetch("kind")
      when "ellipse", "water"
        ellipse_points(surface.fetch("center"), surface.fetch("size"), surface.fetch("rotation_y"), segments: 28)
      when "polygon"
        surface.fetch("points")
      else
        rectangle_points(surface.fetch("center"), surface.fetch("size"), surface.fetch("rotation_y"))
      end
      closed_segments(points).each_with_index do |(from, to), index|
        segment_part(
          builder, from, to, width: width, height: height, material: material,
          name: "Surface border #{index + 1}", vertical_offset: height / 2.0
        )
      end
    end

    def compile_path_borders(builder, route, points)
      width = route["border_width"]
      height = route["border_height"]
      material = route["border_material"]
      return unless width && height && material

      points.each_cons(2).with_index do |(from, to), index|
        dx = to[0] - from[0]
        dz = to[2] - from[2]
        horizontal = Math.sqrt(dx * dx + dz * dz)
        next if horizontal < 0.001

        normal = [dz / horizontal, 0, -dx / horizontal]
        offset = route.fetch("width") / 2.0 + width / 2.0
        [-1, 1].each do |side|
          shifted_from = add_vector(from, multiply_vector(normal, offset * side))
          shifted_to = add_vector(to, multiply_vector(normal, offset * side))
          segment_part(
            builder, shifted_from, shifted_to, width: width, height: height,
            material: material, name: "Path border #{index + 1}", vertical_offset: height / 2.0
          )
        end
      end
    end

    def compile_formal_garden(builder, pattern)
      center = pattern.fetch("center")
      yaw = pattern.fetch("rotation_y")
      width = pattern.fetch("width")
      depth = pattern.fetch("depth")
      petal_count = pattern.fetch("petal_count")
      center_radius = pattern.fetch("center_radius")
      path_width = pattern.fetch("path_width")
      bed_height = pattern.fetch("bed_height")
      border_width = pattern.fetch("border_width")
      border_height = pattern.fetch("border_height")
      density = pattern.fetch("flower_density")
      palette = pattern.fetch("palette")
      garden_radius = [width, depth].min / 2.0
      bed_length = [garden_radius - center_radius - path_width * 1.8, garden_radius * 0.42].max
      bed_width = [[Math::PI * garden_radius * 0.64 / petal_count - path_width, garden_radius * 0.18].max, garden_radius * 0.5].min
      radial_distance = center_radius + path_width + bed_length / 2.0

      builder.part(
        name: "Central plaza", shape: "cylinder", position: add_vector(center, [0, 0.08, 0]),
        size: [(center_radius + path_width) * 2.0, 0.18, (center_radius + path_width) * 2.0],
        material: "path"
      )
      compile_circular_border(
        builder, center, center_radius + path_width, border_width, border_height,
        "stone", yaw, "Central plaza border"
      )

      petal_count.times do |index|
        angle = index * 360.0 / petal_count
        radians = angle * Math::PI / 180.0
        local_center = [Math.sin(radians) * radial_distance, 0, Math.cos(radians) * radial_distance]
        petal_center = builder.world(center, local_center, yaw)
        compile_petal_bed(
          builder, petal_center, yaw + angle, bed_length, bed_width, bed_height,
          border_width, border_height, palette, density, index
        )
      end

      pattern.fetch("ring_count").times do |index|
        radius = center_radius + path_width + bed_length + path_width * (0.7 + index)
        break if radius > garden_radius

        compile_ring_path(builder, center, radius, path_width * 0.72, yaw, "Garden ring #{index + 1}")
      end

      return unless pattern.fetch("central_arch")

      arch_base = builder.world(center, [0, 0, -garden_radius + path_width], yaw)
      Components.arch(builder, {
        "position" => arch_base, "rotation_y" => yaw, "scale" => [1, 1, 1],
        "params" => {
          "width" => [path_width * 2.1, 8.0].max, "depth" => [path_width, 3.5].max,
          "height" => [garden_radius * 0.33, 11.0].max, "material" => "metal",
          "roof_material" => "stone"
        }
      })
    end

    def compile_petal_bed(builder, center, yaw, length, width, bed_height, border_width, border_height, palette, density, petal_index)
      slices = 12
      half_length = length / 2.0
      boundary_left = []
      boundary_right = []
      slices.times do |index|
        t = (index + 0.5) / slices.to_f
        envelope = Math.sin(Math::PI * t)**0.58
        slice_width = [width * envelope, border_width * 1.5].max
        z = -half_length + (index + 0.5) * length / slices
        position = builder.world(center, [0, bed_height / 2.0, z], yaw)
        builder.part(
          name: "Petal soil #{petal_index + 1}.#{index + 1}", shape: "block", position: position,
          size: [slice_width, bed_height, length / slices + 0.08], rotation: [0, yaw, 0],
          material: "earth", collidable: true
        )
      end

      (0..slices).each do |index|
        t = index / slices.to_f
        envelope = Math.sin(Math::PI * t)**0.58
        z = -half_length + t * length
        half_width = [width * envelope / 2.0, border_width / 2.0].max
        boundary_left << builder.world(center, [-half_width, bed_height, z], yaw)
        boundary_right << builder.world(center, [half_width, bed_height, z], yaw)
      end
      [boundary_left, boundary_right].each_with_index do |boundary, side|
        boundary.each_cons(2).with_index do |(from, to), index|
          segment_part(
            builder, from, to, width: border_width, height: border_height,
            material: "stone", name: "Petal border #{petal_index + 1}.#{side + 1}.#{index + 1}",
            vertical_offset: border_height / 2.0
          )
          segment_part(
            builder, from, to, width: [border_width * 1.15, 0.55].max, height: [bed_height * 1.4, 1.05].min,
            material: "evergreen", name: "Clipped petal hedge #{petal_index + 1}.#{side + 1}.#{index + 1}",
            vertical_offset: border_height + [bed_height * 0.7, 0.525].min
          )
        end
      end
      [[boundary_left.first, boundary_right.first], [boundary_left.last, boundary_right.last]].each_with_index do |(from, to), index|
        segment_part(
          builder, from, to, width: border_width, height: border_height,
          material: "stone", name: "Petal tip #{petal_index + 1}.#{index + 1}",
          vertical_offset: border_height / 2.0
        )
        segment_part(
          builder, from, to, width: [border_width * 1.15, 0.55].max, height: [bed_height * 1.4, 1.05].min,
          material: "evergreen", name: "Clipped petal tip #{petal_index + 1}.#{index + 1}",
          vertical_offset: border_height + [bed_height * 0.7, 0.525].min
        )
      end

      flower_count = [(length * width * density * 0.15).round, 16].max.clamp(16, 44)
      flower_count.times do |index|
        local_z = builder.rng.rand(-half_length * 0.88..half_length * 0.88)
        t = (local_z + half_length) / length
        allowed_half_width = width * (Math.sin(Math::PI * t)**0.58) * 0.42
        local_x = builder.rng.rand(-allowed_half_width..allowed_half_width)
        base = builder.world(center, [local_x, bed_height, local_z], yaw)
        bloom = palette[(petal_index + index / 7) % palette.length]
        scale = builder.rng.rand(0.72..1.15)
        builder.part(
          name: "Flower foliage #{petal_index + 1}.#{index + 1}", shape: "ball",
          position: add_vector(base, [0, 0.32 * scale, 0]), size: [0.9 * scale, 0.55 * scale, 0.9 * scale],
          material: "foliage", collidable: false
        )
        builder.part(
          name: "Flower bloom #{petal_index + 1}.#{index + 1}", shape: "ball",
          position: add_vector(base, [0, 0.68 * scale, 0]), size: [0.62 * scale, 0.38 * scale, 0.62 * scale],
          material: bloom, collidable: false
        )
      end
    end

    def compile_ring_path(builder, center, radius, width, yaw, name)
      points = ellipse_points(center, [radius * 2.0, radius * 2.0], yaw, segments: 32)
      closed_segments(points).each_with_index do |(from, to), index|
        segment_part(builder, from, to, width: width, height: 0.16, material: "path", name: "#{name} #{index + 1}", vertical_offset: 0.02)
      end
    end

    def compile_circular_border(builder, center, radius, width, height, material, yaw, name)
      points = ellipse_points(center, [radius * 2.0, radius * 2.0], yaw, segments: 28)
      closed_segments(points).each_with_index do |(from, to), index|
        segment_part(builder, from, to, width: width, height: height, material: material, name: "#{name} #{index + 1}", vertical_offset: height / 2.0)
      end
    end

    def compile_terrace(builder, pattern)
      center = pattern.fetch("center")
      yaw = pattern.fetch("rotation_y")
      width = pattern.fetch("width")
      depth = pattern.fetch("depth")
      levels = pattern.fetch("levels")
      rise = pattern.fetch("rise")
      run = depth / levels
      levels.times do |index|
        level_width = width * (1.0 - index * 0.035)
        level_depth = depth - index * run
        local_center = [0, index * rise - rise / 2.0, -index * run / 2.0]
        builder.part(
          name: "Terrace level #{index + 1}", shape: "block", position: builder.world(center, local_center, yaw),
          size: [level_width, rise, level_depth], rotation: [0, yaw, 0], material: pattern.fetch("material")
        )
        edge_position = builder.world(center, [0, index * rise + rise / 2.0, level_depth / 2.0 - index * run / 2.0], yaw)
        builder.part(
          name: "Terrace retaining edge #{index + 1}", shape: "block", position: edge_position,
          size: [level_width, rise * 1.15, 0.45], rotation: [0, yaw, 0], material: pattern.fetch("edge_material")
        )
      end
    end

    def compile_mountain_ridge(builder, pattern)
      center = pattern.fetch("center")
      yaw = pattern.fetch("rotation_y")
      width = pattern.fetch("width")
      depth = pattern.fetch("depth")
      height = pattern.fetch("height")
      count = pattern.fetch("peak_count")
      material = pattern.fetch("material")
      spacing = width / [count - 1, 1].max
      count.times do |index|
        x = -width / 2.0 + index * spacing
        edge_factor = 0.68 + Math.sin(Math::PI * index / [count - 1, 1].max) * 0.32
        peak_height = height * edge_factor * builder.rng.rand(0.78..1.08)
        peak_width = spacing * builder.rng.rand(1.55..2.15)
        position = builder.world(center, [x, peak_height * 0.38, builder.rng.rand(-depth * 0.12..depth * 0.12)], yaw)
        builder.part(
          name: "Ridge peak #{index + 1}", shape: "ball", position: position,
          size: [peak_width, peak_height, depth * builder.rng.rand(0.75..1.1)],
          rotation: [0, yaw, 0], material: material, collidable: false
        )
      end
    end

    def compile_forest_frame(builder, pattern)
      center = pattern.fetch("center")
      yaw = pattern.fetch("rotation_y")
      count = pattern.fetch("count")
      width = pattern.fetch("width")
      depth = pattern.fetch("depth")
      minimum = pattern.fetch("min_height")
      maximum = pattern.fetch("max_height")
      evergreen_ratio = pattern.fetch("evergreen_ratio")
      count.times do |index|
        side = index.even? ? -1 : 1
        local = [side * builder.rng.rand(width * 0.28..width * 0.5), 0, builder.rng.rand(-depth / 2.0..depth / 2.0)]
        position = builder.world(center, local, yaw)
        height = builder.rng.rand(minimum..maximum)
        object = {
          "position" => position, "rotation_y" => builder.rng.rand(0.0..360.0), "scale" => [1, 1, 1],
          "params" => {
            "trunk_height" => height, "trunk_diameter" => [height * 0.075, 0.65].max,
            "canopy_radius" => height * 0.31
          }
        }
        builder.rng.rand < evergreen_ratio ? Components.conifer(builder, object) : Components.tree(builder, object)
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

    def catmull_rom(points, subdivisions:)
      return points if points.length < 3

      result = []
      (0...(points.length - 1)).each do |index|
        p0 = points[[index - 1, 0].max]
        p1 = points[index]
        p2 = points[index + 1]
        p3 = points[[index + 2, points.length - 1].min]
        subdivisions.times do |step|
          t = step.to_f / subdivisions
          result << 3.times.map { |axis| catmull_value(p0[axis], p1[axis], p2[axis], p3[axis], t) }
        end
      end
      result << points.last
      result
    end

    def catmull_value(p0, p1, p2, p3, t)
      0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t**2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t**3)
    end

    def segment_part(builder, from, to, width:, height:, material:, name:, vertical_offset: 0.0)
      dx = to[0] - from[0]
      dy = to[1] - from[1]
      dz = to[2] - from[2]
      horizontal = Math.sqrt(dx * dx + dz * dz)
      length = Math.sqrt(dx * dx + dy * dy + dz * dz)
      return if length < 0.001

      yaw = Math.atan2(dx, dz) * 180.0 / Math::PI
      pitch = -Math.atan2(dy, [horizontal, 0.001].max) * 180.0 / Math::PI
      builder.part(
        name: name, shape: "block",
        position: [(from[0] + to[0]) / 2.0, (from[1] + to[1]) / 2.0 + vertical_offset, (from[2] + to[2]) / 2.0],
        size: [width, height, length + 0.08], rotation: [pitch, yaw, 0], material: material
      )
    end

    def ellipse_points(center, size, yaw, segments:)
      segments.times.map do |index|
        angle = 2.0 * Math::PI * index / segments
        local = [Math.cos(angle) * size[0] / 2.0, 0, Math.sin(angle) * size[1] / 2.0]
        radians = yaw * Math::PI / 180.0
        [
          center[0] + local[0] * Math.cos(radians) + local[2] * Math.sin(radians),
          center[1],
          center[2] - local[0] * Math.sin(radians) + local[2] * Math.cos(radians)
        ]
      end
    end

    def rectangle_points(center, size, yaw)
      half_width = size[0] / 2.0
      half_depth = size[1] / 2.0
      builder = Struct.new(:base) do
        def world(local, degrees)
          radians = degrees * Math::PI / 180.0
          [
            base[0] + local[0] * Math.cos(radians) + local[2] * Math.sin(radians),
            base[1] + local[1],
            base[2] - local[0] * Math.sin(radians) + local[2] * Math.cos(radians)
          ]
        end
      end.new(center)
      [[-half_width, 0, -half_depth], [half_width, 0, -half_depth], [half_width, 0, half_depth], [-half_width, 0, half_depth]].map do |local|
        builder.world(local, yaw)
      end
    end

    def closed_segments(points)
      points.each_with_index.map { |point, index| [point, points[(index + 1) % points.length]] }
    end

    def add_vector(left, right)
      left.zip(right).map { |a, b| a.to_f + b.to_f }
    end

    def multiply_vector(vector, scalar)
      vector.map { |value| value.to_f * scalar }
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
