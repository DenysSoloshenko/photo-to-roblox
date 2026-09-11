require "test_helper"
require "rexml/document"

class RobloxExporterTest < ActiveSupport::TestCase
  test "exports a real editable Roblox XML place without scripts" do
    spec = JSON.parse(Rails.root.join("examples/courtyard.json").read)
    scene_ir = Scene::Compiler.new.compile_scene(spec)
    xml = Roblox::Exporter.new.export(scene_ir)
    document = REXML::Document.new(xml)

    assert_equal "roblox", document.root.name
    assert_equal "4", document.root.attributes["version"]
    assert_equal scene_ir.fetch("parts").length, REXML::XPath.match(document, "//Item[@class='Part'] | //Item[@class='SpawnLocation']").length
    assert_equal 1, REXML::XPath.match(document, "//Item[@class='SpawnLocation']").length
    assert_empty REXML::XPath.match(document, "//Item[@class='Script'] | //Item[@class='LocalScript'] | //Item[@class='ModuleScript']")
    assert REXML::XPath.match(document, "//CoordinateFrame[@name='CFrame']").any?
    assert REXML::XPath.match(document, "//Item[@class='Model']/Properties/string[@name='Name']").any? { |node| node.text == "main_house" }
  end
end
