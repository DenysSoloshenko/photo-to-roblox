require "rexml/document"
require "rexml/formatters/pretty"

module Roblox
  class Exporter
    SHAPES = { "block" => 1, "ball" => 0, "cylinder" => 2 }.freeze

    def export(scene_ir)
      @serial = 0
      document = REXML::Document.new
      document << REXML::XMLDecl.new("1.0", "UTF-8")
      root = document.add_element("roblox", { "xmlns:xmime" => "http://www.w3.org/2005/05/xmlmime", "version" => "4" })
      root.add_element("External").text = "null"
      root.add_element("External").text = "nil"

      workspace, workspace_properties = item(root, "Workspace", "Workspace")
      property(workspace_properties, "float", "Gravity", 196.2)
      property(workspace_properties, "float", "FallenPartsDestroyHeight", -100)
      scene_model, = item(workspace, "Model", safe_name(scene_ir.fetch("name")))

      scene_ir.fetch("parts").group_by { |part| part.fetch("source_id") }.each do |source_id, parts|
        semantic_model, = item(scene_model, "Model", safe_name(source_id))
        parts.each { |part| add_part(semantic_model, part) }
      end

      camera, camera_properties = item(workspace, "Camera", "Camera")
      eye = scene_ir.dig("camera", "position")
      target = scene_ir.dig("camera", "target")
      coordinate_frame(camera_properties, "CFrame", eye, look_at_matrix(eye, target))
      coordinate_frame(camera_properties, "Focus", target, identity_matrix)
      property(camera_properties, "float", "FieldOfView", scene_ir.dig("camera", "fov"))
      property(camera_properties, "token", "CameraType", 0)
      property(workspace_properties, "Ref", "CurrentCamera", camera.attributes.fetch("referent"))

      _, material_properties = item(root, "MaterialService", "MaterialService")
      property(material_properties, "bool", "Use2022Materials", true)
      add_lighting(root)
      _, starter_properties = item(root, "StarterPlayer", "StarterPlayer")
      property(starter_properties, "float", "CameraMinZoomDistance", 2)
      property(starter_properties, "float", "CameraMaxZoomDistance", 180)
      property(starter_properties, "float", "CharacterWalkSpeed", 16)
      %w[Players ReplicatedStorage ServerScriptService Teams].each { |service| item(root, service, service) }

      output = +""
      formatter = REXML::Formatters::Pretty.new(2)
      formatter.compact = true
      formatter.write(document, output)
      output << "\n"
      output
    end

    private

    def add_part(parent, part)
      class_name = part.fetch("class", "Part")
      node, properties = item(parent, class_name, safe_name(part.fetch("name")))
      matrix = rotation_matrix(part.fetch("rotation"), cylinder: part.fetch("shape") == "cylinder")
      coordinate_frame(properties, "CFrame", part.fetch("position"), matrix)
      vector(properties, "size", part.fetch("size"))
      color_uint8(properties, part.fetch("color"))
      property(properties, "token", "Material", Scene::MaterialCatalog.fetch(part.fetch("material")).fetch(:roblox))
      property(properties, "token", "shape", SHAPES.fetch(part.fetch("shape"))) if class_name == "Part"
      property(properties, "bool", "Anchored", true)
      property(properties, "bool", "CanCollide", part.fetch("collidable"))
      property(properties, "bool", "CanTouch", false)
      property(properties, "bool", "CanQuery", true)
      property(properties, "bool", "CastShadow", part.fetch("cast_shadow"))
      property(properties, "float", "Transparency", part.fetch("transparency"))
      property(properties, "float", "Reflectance", 0)
      property(properties, "token", "TopSurface", 0)
      property(properties, "token", "BottomSurface", 0)
      if class_name == "SpawnLocation"
        property(properties, "bool", "Neutral", true)
        property(properties, "bool", "Enabled", true)
        property(properties, "bool", "AllowTeamChangeOnTouch", false)
        property(properties, "float", "Duration", 0)
      end
      node
    end

    def add_lighting(root)
      lighting, properties = item(root, "Lighting", "Lighting")
      property(properties, "float", "ClockTime", 15.25)
      property(properties, "float", "Brightness", 2.2)
      property(properties, "bool", "GlobalShadows", true)
      color(properties, "Ambient", "#687581")
      color(properties, "OutdoorAmbient", "#9aa3a8")
      property(properties, "float", "ExposureCompensation", 0.05)
      property(properties, "float", "GeographicLatitude", 42)
      property(properties, "float", "ShadowSoftness", 0.32)
      property(properties, "float", "FogStart", 400)
      property(properties, "float", "FogEnd", 1_500)
      color(properties, "FogColor", "#bed1dc")
      sky, sky_properties = item(lighting, "Sky", "Clear daylight")
      property(sky_properties, "int", "StarCount", 0)
      sky
    end

    def item(parent, class_name, name)
      @serial += 1
      node = parent.add_element("Item", { "class" => class_name, "referent" => format("RBX%08d", @serial) })
      properties = node.add_element("Properties")
      property(properties, "string", "Name", name)
      [node, properties]
    end

    def property(parent, type, name, value)
      node = parent.add_element(type, { "name" => name })
      node.text = value.is_a?(TrueClass) || value.is_a?(FalseClass) ? value.to_s.downcase : value.to_s
      node
    end

    def vector(parent, name, values)
      node = parent.add_element("Vector3", { "name" => name })
      %w[X Y Z].zip(values).each { |axis, value| node.add_element(axis).text = format_number(value) }
    end

    def color(parent, name, hex)
      values = hex.delete_prefix("#").scan(/../).map { |component| component.to_i(16) / 255.0 }
      node = parent.add_element("Color3", { "name" => name })
      %w[R G B].zip(values).each { |axis, value| node.add_element(axis).text = format_number(value) }
    end

    def color_uint8(parent, hex)
      red, green, blue = hex.delete_prefix("#").scan(/../).map { |component| component.to_i(16) }
      value = (255 << 24) | (red << 16) | (green << 8) | blue
      property(parent, "Color3uint8", "Color3uint8", value)
    end

    def coordinate_frame(parent, name, position, matrix)
      node = parent.add_element("CoordinateFrame", { "name" => name })
      %w[X Y Z].zip(position).each { |axis, value| node.add_element(axis).text = format_number(value) }
      matrix.flatten.each_with_index do |value, index|
        node.add_element("R#{index / 3}#{index % 3}").text = format_number(value)
      end
    end

    def rotation_matrix(rotation, cylinder: false)
      x, y, z = rotation.map { |value| value.to_f * Math::PI / 180.0 }
      matrix = multiply(multiply(axis_y(y), axis_x(x)), axis_z(z))
      cylinder ? multiply(matrix, axis_z(Math::PI / 2.0)) : matrix
    end

    def look_at_matrix(eye, target)
      back = normalize(subtract(eye, target))
      right = normalize(cross([0, 1, 0], back))
      up = cross(back, right)
      [[right[0], up[0], back[0]], [right[1], up[1], back[1]], [right[2], up[2], back[2]]]
    end

    def axis_x(angle)
      cosine, sine = Math.cos(angle), Math.sin(angle)
      [[1, 0, 0], [0, cosine, -sine], [0, sine, cosine]]
    end

    def axis_y(angle)
      cosine, sine = Math.cos(angle), Math.sin(angle)
      [[cosine, 0, sine], [0, 1, 0], [-sine, 0, cosine]]
    end

    def axis_z(angle)
      cosine, sine = Math.cos(angle), Math.sin(angle)
      [[cosine, -sine, 0], [sine, cosine, 0], [0, 0, 1]]
    end

    def multiply(left, right)
      3.times.map { |row| 3.times.map { |column| 3.times.sum { |index| left[row][index] * right[index][column] } } }
    end

    def identity_matrix
      [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    end

    def subtract(left, right)
      left.zip(right).map { |a, b| a.to_f - b.to_f }
    end

    def cross(left, right)
      [left[1] * right[2] - left[2] * right[1], left[2] * right[0] - left[0] * right[2], left[0] * right[1] - left[1] * right[0]]
    end

    def normalize(vector)
      length = Math.sqrt(vector.sum { |value| value * value })
      length < 0.0001 ? [1, 0, 0] : vector.map { |value| value / length }
    end

    def safe_name(value)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace).gsub(/[\u0000-\u001f]/, "")[0, 100]
    end

    def format_number(value)
      format("%.8g", value.to_f)
    end
  end
end
