require "test_helper"
require "nokogiri"

class NeighbourhoodCaseTest < ActiveSupport::TestCase
  DIRECTORY = Rails.root.join("frontend/public/cases/springer-park")

  test "public geometry is finite, reproducible metadata and contains no executable assets" do
    scene = JSON.parse(DIRECTORY.join("scene.json").read)
    metrics = JSON.parse(DIRECTORY.join("metrics.json").read)
    source = JSON.parse(DIRECTORY.join("source.json").read)
    assert_equal 5682, scene.fetch("parts").length
    assert_equal metrics.fetch("part_count"), scene.fetch("parts").length
    assert_equal metrics.fetch("building_count"), source.fetch("features").count { |f| f["kind"] == "building" }
    assert_equal false, metrics.fetch("studio_play_tested")
    assert_includes scene.fetch("attribution"), "OpenStreetMap"
    assert_equal scene.fetch("parts").length, scene.fetch("parts").map { |p| p["id"] }.uniq.length
    assert scene.fetch("parts").all? { |p| %w[position size rotation].all? { |key| p[key].length == 3 && p[key].all? { |v| v.is_a?(Numeric) && v.finite? } } && p["size"].all?(&:positive?) }
    assert_equal 1, scene.fetch("parts").count { |p| p["class"] == "SpawnLocation" }
    assert_empty scene.fetch("parts").select { |p| (p.keys & %w[script mesh_id texture_id asset_id]).any? }
  end

  test "public Roblox export matches the preview and carries attribution without scripts" do
    document = Nokogiri::XML(DIRECTORY.join("Springer_Park_Open_Data.rbxlx").read) { |config| config.strict.nonet }
    items = document.xpath("//Item")
    parts = items.select { |item| %w[Part SpawnLocation].include?(item["class"]) }
    assert_equal "roblox", document.root.name
    assert_equal "4", document.root["version"]
    assert_equal 5682, parts.length
    assert_equal 1, items.count { |item| item["class"] == "SpawnLocation" }
    assert_empty items.select { |item| %w[Script LocalScript ModuleScript MeshPart SpecialMesh Decal Texture].include?(item["class"]) }
    assert parts.all? { |part| part.at_xpath("Properties/bool[@name='Anchored']")&.text == "true" }
    credits = items.find { |item| item["class"] == "TextLabel" }
    assert_includes credits.at_xpath("Properties/string[@name='Text']").text, "openstreetmap.org/copyright"
  end
end
