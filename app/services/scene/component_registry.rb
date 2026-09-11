require "digest"

module Scene
  class ComponentRegistry
    def self.default
      registry = new
      registry.register("tree") { |builder, object| Components.tree(builder, object) }
      registry.register("bush") { |builder, object| Components.bush(builder, object) }
      registry.register("flower") { |builder, object| Components.flower(builder, object) }
      registry.register("hedge") { |builder, object| Components.hedge(builder, object) }
      registry.register("conifer") { |builder, object| Components.conifer(builder, object) }
      registry.register("arch") { |builder, object| Components.arch(builder, object) }
      registry.register("mountain") { |builder, object| Components.mountain(builder, object) }
      registry.register("rock") { |builder, object| Components.rock(builder, object) }
      registry.register("bench") { |builder, object| Components.bench(builder, object) }
      registry.register("fence") { |builder, object| Components.fence(builder, object) }
      registry.register("building") { |builder, object| Components.building(builder, object) }
      registry.register("mass") { |builder, object| Components.mass(builder, object) }
      registry
    end

    def initialize
      @components = {}
    end

    def register(type, &compiler)
      raise ArgumentError, "component #{type.inspect} already registered" if @components.key?(type)

      @components[type] = compiler
    end

    def compile(builder, object)
      @components.fetch(object.fetch("type")).call(builder, object)
    end
  end

  class PartBuilder
    attr_reader :parts, :rng, :source_id

    def initialize(parts:, source_id:, seed:)
      @parts = parts
      @source_id = source_id
      @rng = Random.new(seed)
      @sequence = 0
    end

    def part(name:, shape:, position:, size:, rotation: [0, 0, 0], material:, transparency: 0.0, collidable: true, cast_shadow: true)
      @sequence += 1
      definition = MaterialCatalog.fetch(material)
      parts << {
        "id" => "#{source_id}:#{slug(name)}:#{@sequence}",
        "source_id" => source_id,
        "group" => source_id,
        "name" => name,
        "shape" => shape,
        "position" => numbers(position),
        "size" => numbers(size),
        "rotation" => numbers(rotation),
        "material" => material,
        "color" => definition.fetch(:color),
        "transparency" => transparency.to_f.round(5),
        "collidable" => !!collidable,
        "cast_shadow" => !!cast_shadow
      }
    end

    def world(base, local, yaw_degrees)
      angle = yaw_degrees.to_f * Math::PI / 180.0
      cosine = Math.cos(angle)
      sine = Math.sin(angle)
      [
        base[0] + local[0] * cosine + local[2] * sine,
        base[1] + local[1],
        base[2] - local[0] * sine + local[2] * cosine
      ]
    end

    private

    def numbers(values)
      values.map { |value| value.to_f.round(5) }
    end

    def slug(value)
      value.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\-\z/, "")
    end
  end

  module Components
    module_function

    def tree(builder, object)
      base, yaw, scale, params = unpack(object)
      trunk_height = numeric(params, "trunk_height", 6.0) * scale[1]
      trunk_diameter = numeric(params, "trunk_diameter", 1.2) * (scale[0] + scale[2]) / 2.0
      canopy_radius = numeric(params, "canopy_radius", 3.7) * (scale[0] + scale[2]) / 2.0
      builder.part(name: "Trunk", shape: "cylinder", position: add(base, [0, trunk_height / 2.0, 0]), size: [trunk_diameter, trunk_height, trunk_diameter], rotation: [0, yaw, 0], material: "bark")
      [[0, 0, 0], [-0.45, -0.2, 0.25], [0.45, -0.15, -0.2], [0.0, 0.45, 0.05]].each_with_index do |offset, index|
        jitter = [builder.rng.rand(-0.18..0.18), builder.rng.rand(-0.12..0.18), builder.rng.rand(-0.18..0.18)]
        center = add(base, [
          (offset[0] + jitter[0]) * canopy_radius,
          trunk_height + (offset[1] + jitter[1]) * canopy_radius + canopy_radius * 0.55,
          (offset[2] + jitter[2]) * canopy_radius
        ])
        diameter = canopy_radius * (index.zero? ? 1.75 : 1.25)
        builder.part(name: "Canopy #{index + 1}", shape: "ball", position: center, size: [diameter, diameter * 0.9, diameter], material: index.even? ? "foliage" : "foliage_light", collidable: false)
      end
    end

    def bush(builder, object)
      base, = unpack(object)
      scale = object.fetch("scale")
      params = object.fetch("params")
      radius = numeric(params, "radius", numeric(params, "canopy_radius", 1.7))
      material = params["material"] || "foliage"
      [[0, 0.7, 0], [-0.65, 0.48, 0.1], [0.58, 0.5, 0.18], [0.05, 0.48, -0.62]].each_with_index do |offset, index|
        size = radius * (index.zero? ? 1.65 : 1.25)
        builder.part(
          name: "Bush crown #{index + 1}", shape: "ball",
          position: add(base, [offset[0] * radius * scale[0], offset[1] * radius * scale[1], offset[2] * radius * scale[2]]),
          size: [size * scale[0], size * 0.85 * scale[1], size * scale[2]],
          material: material == "foliage" && index.odd? ? "foliage_light" : material, collidable: false
        )
      end
    end

    FLOWER_PALETTE = %w[flower_red flower_orange flower_pink flower_yellow flower_purple flower_white].freeze

    def flower(builder, object)
      base, yaw, scale, params = unpack(object)
      height = numeric(params, "height", 2.2) * scale[1]
      radius = numeric(params, "radius", 0.55) * (scale[0] + scale[2]) / 2.0
      bloom_material = params["material"] || "flower_mix"
      bloom_material = FLOWER_PALETTE.sample(random: builder.rng) if bloom_material == "flower_mix"

      builder.part(name: "Stem", shape: "cylinder", position: add(base, [0, height * 0.48, 0]), size: [0.12, height * 0.92, 0.12], rotation: [0, yaw, 0], material: "foliage", collidable: false)
      builder.part(name: "Leaves", shape: "ball", position: add(base, [0, height * 0.38, 0]), size: [radius * 1.6, radius * 0.7, radius * 1.2], rotation: [0, yaw, 18], material: "foliage_light", collidable: false)
      [[0, 1.0, 0], [-0.58, 0.87, 0.24], [0.54, 0.9, -0.2]].each_with_index do |offset, index|
        bloom_size = radius * (index.zero? ? 1.45 : 1.05)
        builder.part(
          name: "Bloom #{index + 1}", shape: "ball",
          position: add(base, [offset[0] * radius, height * offset[1], offset[2] * radius]),
          size: [bloom_size, bloom_size * 0.72, bloom_size], material: bloom_material, collidable: false
        )
      end
    end

    def hedge(builder, object)
      base, yaw, scale, params = unpack(object)
      width = numeric(params, "width", numeric(params, "length", 4.0)) * scale[0]
      depth = numeric(params, "depth", 1.4) * scale[2]
      height = numeric(params, "height", 1.6) * scale[1]
      material = params["material"] || "evergreen"
      builder.part(name: "Clipped hedge", shape: "block", position: add(base, [0, height / 2.0, 0]), size: [width, height, depth], rotation: [0, yaw, 0], material: material, collidable: false)
    end

    def conifer(builder, object)
      base, yaw, scale, params = unpack(object)
      trunk_height = numeric(params, "trunk_height", 14.0) * scale[1]
      trunk_diameter = numeric(params, "trunk_diameter", 1.2) * (scale[0] + scale[2]) / 2.0
      canopy_radius = numeric(params, "canopy_radius", 5.0) * (scale[0] + scale[2]) / 2.0
      builder.part(name: "Trunk", shape: "cylinder", position: add(base, [0, trunk_height / 2.0, 0]), size: [trunk_diameter, trunk_height, trunk_diameter], rotation: [0, yaw, 0], material: "bark")
      4.times do |index|
        fraction = index / 3.0
        diameter = canopy_radius * (2.0 - fraction * 1.15)
        builder.part(
          name: "Evergreen tier #{index + 1}", shape: "ball",
          position: add(base, [0, trunk_height * (0.34 + index * 0.18), 0]),
          size: [diameter, trunk_height * 0.32, diameter], material: "evergreen", collidable: false
        )
      end
    end

    def arch(builder, object)
      base, yaw, scale, params = unpack(object)
      width = numeric(params, "width", 12.0) * scale[0]
      depth = numeric(params, "depth", 5.0) * scale[2]
      height = numeric(params, "height", 15.0) * scale[1]
      material = params["material"] || "metal"
      pedestal_material = params["roof_material"] || "stone"
      radius = width / 2.0
      spring_height = [height - radius, height * 0.42].max
      rail = [[width, depth].min * 0.055, 0.28].max
      segments = 7

      [-depth / 2.0, depth / 2.0].each do |z|
        [-1, 1].each do |side|
          x = side * radius
          builder.part(name: "Stone pedestal", shape: "block", position: builder.world(base, [x, 1.0, z], yaw), size: [rail * 2.4, 2.0, rail * 2.4], rotation: [0, yaw, 0], material: pedestal_material)
          builder.part(name: "Arch post", shape: "block", position: builder.world(base, [x, 1.9 + spring_height / 2.0, z], yaw), size: [rail, spring_height, rail], rotation: [0, yaw, 0], material: material)
        end
        segment_length = Math::PI * radius / segments * 1.08
        segments.times do |index|
          angle = Math::PI * (index + 0.5) / segments
          local = [Math.cos(angle) * radius, spring_height + Math.sin(angle) * radius + 1.9, z]
          builder.part(
            name: "Curved arch", shape: "block", position: builder.world(base, local, yaw),
            size: [segment_length, rail, rail], rotation: [0, yaw, angle * 180.0 / Math::PI - 90.0], material: material
          )
        end
      end
      5.times do |index|
        angle = Math::PI * index / 4.0
        local = [Math.cos(angle) * radius, spring_height + Math.sin(angle) * radius + 1.9, 0]
        builder.part(name: "Arch crossbar", shape: "block", position: builder.world(base, local, yaw), size: [rail, rail, depth], rotation: [0, yaw, 0], material: material)
      end
    end

    def mountain(builder, object)
      base, yaw, scale, params = unpack(object)
      width = numeric(params, "width", numeric(params, "radius", 18.0) * 2.0) * scale[0]
      depth = numeric(params, "depth", width * 0.55) * scale[2]
      height = numeric(params, "height", width * 0.38) * scale[1]
      material = params["material"] || "mountain"
      [[0, 0, 0, 1.0], [-0.3, -0.12, 0.04, 0.7], [0.32, -0.17, -0.03, 0.62]].each_with_index do |(x, y, z, size), index|
        builder.part(
          name: "Mountain mass #{index + 1}", shape: "ball",
          position: add(base, [x * width, height * (0.42 + y), z * depth]),
          size: [width * size, height * size, depth * size], rotation: [0, yaw, 0], material: material, collidable: false
        )
      end
    end

    def rock(builder, object)
      base, yaw, scale, params = unpack(object)
      radius = numeric(params, "radius", 1.6)
      builder.part(name: "Rock", shape: "ball", position: add(base, [0, radius * scale[1] * 0.45, 0]), size: [radius * 2 * scale[0], radius * 1.15 * scale[1], radius * 1.65 * scale[2]], rotation: [8 + builder.rng.rand(-6.0..6.0), yaw, 5 + builder.rng.rand(-5.0..5.0)], material: params["material"] || "stone")
    end

    def bench(builder, object)
      base, yaw, scale, params = unpack(object)
      width = numeric(params, "width", 5.5) * scale[0]
      height = numeric(params, "height", 3.0) * scale[1]
      depth = numeric(params, "depth", 2.0) * scale[2]
      material = params["material"] || "wood"
      builder.part(name: "Seat", shape: "block", position: builder.world(base, [0, height * 0.47, 0], yaw), size: [width, 0.35, depth], rotation: [0, yaw, 0], material: material)
      builder.part(name: "Back", shape: "block", position: builder.world(base, [0, height * 0.75, -depth * 0.43], yaw), size: [width, height * 0.58, 0.3], rotation: [-8, yaw, 0], material: material)
      [-1, 1].each do |side|
        x = side * width * 0.36
        builder.part(name: "Leg", shape: "block", position: builder.world(base, [x, height * 0.23, -depth * 0.28], yaw), size: [0.34, height * 0.46, 0.34], rotation: [0, yaw, 0], material: "metal")
        builder.part(name: "Leg", shape: "block", position: builder.world(base, [x, height * 0.23, depth * 0.28], yaw), size: [0.34, height * 0.46, 0.34], rotation: [0, yaw, 0], material: "metal")
      end
      builder.part(name: "Support", shape: "block", position: builder.world(base, [0, height * 0.26, 0], yaw), size: [width * 0.82, 0.28, 0.28], rotation: [0, yaw, 0], material: "metal")
    end

    def fence(builder, object)
      base, yaw, scale, params = unpack(object)
      length = numeric(params, "length", 16.0) * scale[0]
      height = numeric(params, "height", 4.2) * scale[1]
      spacing = [numeric(params, "post_spacing", 4.0) * scale[0], 1.0].max
      material = params["material"] || "wood"
      post_count = [(length / spacing).ceil + 1, 24].min
      post_count.times do |index|
        x = -length / 2.0 + length * index / (post_count - 1)
        builder.part(name: "Fence post", shape: "block", position: builder.world(base, [x, height / 2.0, 0], yaw), size: [0.38, height, 0.38], rotation: [0, yaw, 0], material: material)
      end
      [height * 0.34, height * 0.76].each do |rail_height|
        builder.part(name: "Fence rail", shape: "block", position: builder.world(base, [0, rail_height, 0], yaw), size: [length, 0.34, 0.3], rotation: [0, yaw, 0], material: material)
      end
    end

    def building(builder, object)
      base, yaw, scale, params = unpack(object)
      width = numeric(params, "width", 20.0) * scale[0]
      depth = numeric(params, "depth", 14.0) * scale[2]
      height = numeric(params, "height", 9.0) * scale[1]
      roof_height = numeric(params, "roof_height", 3.0) * scale[1]
      wall = numeric(params, "wall_thickness", 0.65)
      door_width = [numeric(params, "door_width", 3.5), width * 0.45].min
      door_height = [numeric(params, "door_height", 6.5), height * 0.85].min
      wall_material = params["material"] || "white"
      roof_material = params["roof_material"] || "roof"

      builder.part(name: "Floor", shape: "block", position: builder.world(base, [0, 0.15, 0], yaw), size: [width, 0.3, depth], rotation: [0, yaw, 0], material: "concrete")
      builder.part(name: "Back wall", shape: "block", position: builder.world(base, [0, height / 2.0, -depth / 2.0], yaw), size: [width, height, wall], rotation: [0, yaw, 0], material: wall_material)
      [-1, 1].each do |side|
        builder.part(name: "Side wall", shape: "block", position: builder.world(base, [side * width / 2.0, height / 2.0, 0], yaw), size: [wall, height, depth], rotation: [0, yaw, 0], material: wall_material)
      end
      side_width = (width - door_width) / 2.0
      [-1, 1].each do |side|
        x = side * (door_width / 2.0 + side_width / 2.0)
        builder.part(name: "Front wall", shape: "block", position: builder.world(base, [x, height / 2.0, depth / 2.0], yaw), size: [side_width, height, wall], rotation: [0, yaw, 0], material: wall_material)
      end
      builder.part(name: "Door lintel", shape: "block", position: builder.world(base, [0, door_height + (height - door_height) / 2.0, depth / 2.0], yaw), size: [door_width, height - door_height, wall], rotation: [0, yaw, 0], material: wall_material)

      if params["roof_style"] == "flat"
        builder.part(name: "Flat roof", shape: "block", position: builder.world(base, [0, height + roof_height * 0.2, 0], yaw), size: [width + 1, roof_height * 0.4, depth + 1], rotation: [0, yaw, 0], material: roof_material)
      else
        angle = Math.atan2(roof_height, width / 2.0) * 180.0 / Math::PI
        panel_width = Math.sqrt((width / 2.0)**2 + roof_height**2)
        [-1, 1].each do |side|
          builder.part(name: "Gable roof", shape: "block", position: builder.world(base, [side * width / 4.0, height + roof_height / 2.0, 0], yaw), size: [panel_width + 0.5, 0.4, depth + 1.2], rotation: [0, yaw, side * angle], material: roof_material)
        end
      end
    end

    # Generic solid used to preserve dominant forms that do not have a
    # dedicated semantic component yet (sheds, piers, vehicles, sculptures).
    def mass(builder, object)
      base, yaw, scale, params = unpack(object)
      width = numeric(params, "width", 6.0) * scale[0]
      depth = numeric(params, "depth", 6.0) * scale[2]
      height = numeric(params, "height", 5.0) * scale[1]
      builder.part(
        name: "Generic mass", shape: "block",
        position: builder.world(base, [0, height / 2.0, 0], yaw),
        size: [width, height, depth], rotation: [0, yaw, 0],
        material: params["material"] || "concrete"
      )
    end

    def unpack(object)
      [object.fetch("position").map(&:to_f), object.fetch("rotation_y").to_f, object.fetch("scale").map(&:to_f), object.fetch("params")]
    end

    def numeric(params, key, fallback)
      value = params[key]
      value.is_a?(Numeric) && value.positive? ? value.to_f : fallback
    end

    def add(left, right)
      left.zip(right).map { |a, b| a.to_f + b.to_f }
    end
  end
end
