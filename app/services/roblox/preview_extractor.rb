require "digest"
require "rexml/document"
require "rexml/xpath"

module Roblox
  class PreviewExtractor
    MAX_PARTS = 1_500
    PART_CLASSES = %w[Part SpawnLocation WedgePart CornerWedgePart MeshPart UnionOperation].freeze
    SHAPES = { "0" => "ball", "1" => "block", "2" => "cylinder" }.freeze
    MATERIALS = Scene::MaterialCatalog::MATERIALS.each_with_object({}) do |(name, attributes), catalog|
      catalog[attributes.fetch(:roblox).to_s] ||= name
    end.freeze

    def extract(xml, fallback_name: "Roblox map")
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      document = REXML::Document.new(xml)
      nodes = REXML::XPath.match(document, "//Item").select { |item| PART_CLASSES.include?(item.attributes["class"]) }
      raise ArgumentError, "The Roblox map does not contain previewable parts" if nodes.empty?
      raise ArgumentError, "The Roblox map contains more than #{MAX_PARTS} previewable parts" if nodes.length > MAX_PARTS

      parts = nodes.each_with_index.map { |item, index| extract_part(item, index) }
      bounds = calculate_bounds(parts)
      camera = extract_camera(document) || default_camera(bounds)
      spawn_part = parts.find { |part| part["class"] == "SpawnLocation" }
      name = property_text(REXML::XPath.first(document, "//Item[@class='Workspace']/Item[@class='Model']"), "Name").presence || fallback_name

      {
        "version" => "1.0",
        "component_version" => "imported-rbxlx-1",
        "name" => name,
        "seed" => 0,
        "spec_digest" => Digest::SHA256.hexdigest(xml),
        "bounds" => bounds,
        "parts" => parts,
        "spawn" => {
          "position" => spawn_part&.fetch("position") || [0, 3, 0],
          "rotation_y" => spawn_part&.dig("rotation", 1) || 0
        },
        "camera" => camera,
        "stats" => {
          "part_count" => parts.length,
          "triangle_estimate" => parts.sum { |part| part["shape"] == "block" ? 12 : 96 },
          "compile_ms" => ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round(2)
        }
      }
    rescue REXML::ParseException => error
      raise ArgumentError, "Result is not a valid .rbxlx XML file: #{error.message.lines.first.to_s.strip}"
    end

    private

    def extract_part(item, index)
      class_name = item.attributes["class"].to_s
      frame = property_node(item, "CFrame")
      matrix = frame ? matrix_from(frame) : identity_matrix
      size = vector(property_node(item, "size"), [1, 1, 1])
      shape = shape_for(item, class_name)
      if shape == "cylinder"
        size = [size[1], size[0], size[2]]
        matrix = multiply(matrix, axis_z(-Math::PI / 2.0))
      end
      parent_name = property_text(item.parent, "Name").presence || "Imported"
      name = property_text(item, "Name").presence || "Part #{index + 1}"

      {
        "id" => "imported-#{index + 1}",
        "source_id" => safe_id(parent_name, index),
        "group" => "imported",
        "name" => name,
        "shape" => shape,
        "position" => frame ? vector(frame, [0, 0, 0]) : [0, 0, 0],
        "size" => size.map { |value| [value.abs, 0.02].max.round(5) },
        "rotation" => euler_yxz(matrix),
        "material" => material_for(item),
        "color" => color_for(item),
        "transparency" => number_property(item, "Transparency", 0.0).clamp(0.0, 1.0),
        "collidable" => boolean_property(item, "CanCollide", true),
        "cast_shadow" => boolean_property(item, "CastShadow", true)
      }.tap { |part| part["class"] = "SpawnLocation" if class_name == "SpawnLocation" }
    end

    def shape_for(item, class_name)
      return "wedge" if class_name.in?(%w[WedgePart CornerWedgePart])
      return "block" if class_name.in?(%w[MeshPart UnionOperation])

      SHAPES.fetch(property_text(item, "shape"), "block")
    end

    def material_for(item)
      MATERIALS.fetch(property_text(item, "Material"), "concrete")
    end

    def color_for(item)
      encoded = property_text(item, "Color3uint8")
      if encoded.present?
        value = encoded.to_i & 0xffffffff
        return format("#%02x%02x%02x", (value >> 16) & 255, (value >> 8) & 255, value & 255)
      end

      node = property_node(item, "Color")
      return Scene::MaterialCatalog.fetch(material_for(item)).fetch(:color) unless node

      values = %w[R G B].map { |axis| (node.elements[axis]&.text.to_f * 255).round.clamp(0, 255) }
      format("#%02x%02x%02x", *values)
    end

    def extract_camera(document)
      camera = REXML::XPath.first(document, "//Item[@class='Camera']")
      frame = property_node(camera, "CFrame")
      focus = property_node(camera, "Focus")
      return unless frame && focus

      {
        "position" => vector(frame, [0, 50, 80]),
        "target" => vector(focus, [0, 0, 0]),
        "fov" => number_property(camera, "FieldOfView", 55).clamp(20, 100)
      }
    end

    def default_camera(bounds)
      span = [bounds.fetch("width"), bounds.fetch("depth"), 20].max
      { "position" => [span * 0.72, [bounds.fetch("max_height") * 1.25, 22].max, span * 0.92], "target" => [0, bounds.fetch("max_height") * 0.25, 0], "fov" => 50 }
    end

    def calculate_bounds(parts)
      min_x, max_x = parts.map { |part| [part.dig("position", 0) - part.dig("size", 0) / 2.0, part.dig("position", 0) + part.dig("size", 0) / 2.0] }.flatten.minmax
      min_z, max_z = parts.map { |part| [part.dig("position", 2) - part.dig("size", 2) / 2.0, part.dig("position", 2) + part.dig("size", 2) / 2.0] }.flatten.minmax
      max_y = parts.map { |part| part.dig("position", 1) + part.dig("size", 1) / 2.0 }.max
      { "width" => [(max_x - min_x).round(3), 1].max, "depth" => [(max_z - min_z).round(3), 1].max, "max_height" => [max_y.round(3), 1].max }
    end

    def property_node(item, name)
      return unless item
      REXML::XPath.first(item, "Properties/*[@name='#{name}']")
    end

    def property_text(item, name)
      property_node(item, name)&.text.to_s
    end

    def number_property(item, name, fallback)
      text = property_text(item, name)
      text.present? ? text.to_f : fallback
    end

    def boolean_property(item, name, fallback)
      text = property_text(item, name)
      return fallback if text.blank?
      text == "true"
    end

    def vector(node, fallback)
      return fallback unless node
      %w[X Y Z].map.with_index { |axis, index| node.elements[axis]&.text&.to_f || fallback[index] }
    end

    def matrix_from(node)
      3.times.map { |row| 3.times.map { |column| node.elements["R#{row}#{column}"]&.text&.to_f || identity_matrix[row][column] } }
    end

    def euler_yxz(matrix)
      x = Math.asin((-matrix[1][2]).clamp(-1.0, 1.0))
      if matrix[1][2].abs < 0.9999999
        y = Math.atan2(matrix[0][2], matrix[2][2])
        z = Math.atan2(matrix[1][0], matrix[1][1])
      else
        y = Math.atan2(-matrix[2][0], matrix[0][0])
        z = 0
      end
      [x, y, z].map { |angle| (angle * 180.0 / Math::PI).round(5) }
    end

    def safe_id(value, index)
      value.to_s.parameterize.presence || "imported-#{index + 1}"
    end

    def identity_matrix
      [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
    end

    def axis_z(angle)
      cosine, sine = Math.cos(angle), Math.sin(angle)
      [[cosine, -sine, 0], [sine, cosine, 0], [0, 0, 1]]
    end

    def multiply(left, right)
      3.times.map { |row| 3.times.map { |column| 3.times.sum { |index| left[row][index] * right[index][column] } } }
    end
  end
end
