# Run with: bundle exec rails runner scripts/export_neighbourhood_case.rb
require "json"
require "rexml/document"

directory = Rails.root.join("frontend/public/cases/springer-park")
scene = JSON.parse(directory.join("scene.json").read)
document = REXML::Document.new(Roblox::Exporter.new.export(scene))
document.context[:attribute_quote] = :quote

# Attribution travels with the place and remains visible in Play without scripts.
root = document.root
gui = root.add_element("Item", { "class" => "StarterGui", "referent" => "CASE_STARTER_GUI" })
gui.add_element("Properties").add_element("string", { "name" => "Name" }).text = "StarterGui"
screen = gui.add_element("Item", { "class" => "ScreenGui", "referent" => "CASE_CREDITS_GUI" })
props = screen.add_element("Properties")
props.add_element("string", { "name" => "Name" }).text = "Source attribution"
props.add_element("bool", { "name" => "ResetOnSpawn" }).text = "false"
label = screen.add_element("Item", { "class" => "TextLabel", "referent" => "CASE_CREDITS_TEXT" })
props = label.add_element("Properties")
props.add_element("string", { "name" => "Name" }).text = "OpenStreetMap attribution"
props.add_element("string", { "name" => "Text" }).text = "Map data © OpenStreetMap contributors · openstreetmap.org/copyright · ODbL 1.0 | Procedural study — approximate"
props.add_element("float", { "name" => "TextSize" }).text = "12"
props.add_element("float", { "name" => "BackgroundTransparency" }).text = "0.15"
props.add_element("bool", { "name" => "TextWrapped" }).text = "true"
props.add_element("Color3uint8", { "name" => "TextColor3" }).text = "4294967295"
props.add_element("Color3uint8", { "name" => "BackgroundColor3" }).text = "4280300085"
{ "Size" => [1, 0, 0, 38], "Position" => [0, 0, 1, -38] }.each do |name, values|
  node = props.add_element("UDim2", { "name" => name })
  %w[XS XO YS YO].zip(values).each { |key, value| node.add_element(key).text = value.to_s }
end
output = +""
formatter = REXML::Formatters::Pretty.new(2)
formatter.compact = true
formatter.write(root, output)
directory.join("Springer_Park_Open_Data.rbxlx").write(output + "\n")
puts "Exported #{scene.fetch('parts').length} parts; no scripts or external assets"
