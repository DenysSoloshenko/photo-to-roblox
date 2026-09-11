require "test_helper"
require "base64"
require "digest"
require "rexml/document"

class RobloxMapArtifactTest < ActiveSupport::TestCase
  test "builds a verifiable script-free rbxlx artifact with a safe filename" do
    spec = JSON.parse(Rails.root.join("examples/courtyard.json").read)
    spec["name"] = "  My / Unsafe: Place 2026!  "
    scene_ir = Scene::Compiler.new.compile_scene(spec)

    artifact = Roblox::MapArtifact.build(scene_ir)
    xml = Base64.strict_decode64(artifact.fetch("data"))
    document = REXML::Document.new(xml)

    assert_equal "my-unsafe-place-2026.rbxlx", artifact.fetch("filename")
    assert_match(/\A[a-z0-9-]+\.rbxlx\z/, artifact.fetch("filename"))
    assert_equal "application/xml", artifact.fetch("media_type")
    assert_equal "base64", artifact.fetch("encoding")
    assert_equal xml.bytesize, artifact.fetch("byte_size")
    assert_equal Digest::SHA256.hexdigest(xml), artifact.fetch("sha256")
    assert_equal scene_ir.fetch("spec_digest"), artifact.fetch("spec_digest")
    assert_equal "roblox", document.root.name
    assert_empty REXML::XPath.match(document, "//Item[@class='Script'] | //Item[@class='LocalScript'] | //Item[@class='ModuleScript']")
  end
end
