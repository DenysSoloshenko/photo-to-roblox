require "test_helper"

class RobloxPreviewExtractorTest < ActiveSupport::TestCase
  test "rejects nonfinite geometry instead of producing a server error" do
    xml = file_fixture("result.rbxlx").read.sub(/<X>[^<]+<\/X>/, "<X>1e999</X>")
    assert_raises(ArgumentError) { Roblox::PreviewExtractor.new.extract(xml) }
  end
  test "rejects executable instances anywhere in the original download" do
    %w[Script LocalScript ModuleScript].each do |class_name|
      xml = file_fixture("result.rbxlx").read.sub("</roblox>", "<Item class=\"#{class_name}\"><Properties/></Item></roblox>")
      assert_raises(ArgumentError) { Roblox::PreviewExtractor.new.extract(xml) }
    end
  end

  test "rejects doctypes and non Roblox roots" do
    assert_raises(ArgumentError) do
      Roblox::PreviewExtractor.new.extract('<!DOCTYPE roblox [<!ENTITY secret SYSTEM "file:///etc/passwd">]>' + file_fixture("result.rbxlx").read)
    end
    assert_raises(ArgumentError) do
      Roblox::PreviewExtractor.new.extract(file_fixture("result.rbxlx").read.gsub("roblox", "other"))
    end
  end

  test "extracts a browser preview from an rbxlx map" do
    scene = Roblox::PreviewExtractor.new.extract(file_fixture("result.rbxlx").read)

    assert_equal "Customer garden", scene.fetch("name")
    assert_equal 1, scene.dig("stats", "part_count")
    assert_equal 1, scene.dig("stats", "source_part_count")
    assert_equal false, scene.dig("stats", "preview_sampled")
    assert_equal "block", scene.dig("parts", 0, "shape")
    assert_equal [8.0, 0.5, 20.0], scene.dig("parts", 0, "size")
    assert_equal [24.0, 18.0, 30.0], scene.dig("camera", "position")
  end

  test "samples large maps while retaining a representative browser preview" do
    count = Roblox::PreviewExtractor::MAX_PARTS + 2
    parts = Array.new(count) do |index|
      <<~XML
        <Item class="Part">
          <Properties>
            <string name="Name">Part #{index}</string>
            <CoordinateFrame name="CFrame"><X>#{index}</X><Y>0</Y><Z>0</Z></CoordinateFrame>
            <Vector3 name="size"><X>1</X><Y>1</Y><Z>1</Z></Vector3>
          </Properties>
        </Item>
      XML
    end.join
    xml = "<roblox><Item class=\"Workspace\"><Properties/><Item class=\"Model\"><Properties><string name=\"Name\">Large map</string></Properties>#{parts}</Item></Item></roblox>"

    scene = Roblox::PreviewExtractor.new.extract(xml)

    assert_equal Roblox::PreviewExtractor::MAX_PARTS, scene.dig("stats", "part_count")
    assert_equal count, scene.dig("stats", "source_part_count")
    assert_equal true, scene.dig("stats", "preview_sampled")
    assert_equal "Part 0", scene.dig("parts", 0, "name")
    assert_equal "Part #{count - 2}", scene.dig("parts", -1, "name")

    # The final part is deliberately outside the sample, but still belongs
    # to the downloadable file and must be validated.
    invalid_xml = xml.sub("<X>#{count - 1}</X>", "<X>1e999</X>")
    assert_raises(ArgumentError) { Roblox::PreviewExtractor.new.extract(invalid_xml) }
  end
end
