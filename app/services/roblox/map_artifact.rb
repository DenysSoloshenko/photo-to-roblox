require "base64"
require "digest"

module Roblox
  class MapArtifact
    MAX_BYTES = 8 * 1024 * 1024

    class TooLarge < StandardError; end

    def self.build(scene_ir)
      xml = Exporter.new.export(scene_ir)
      raise TooLarge, "compiled Roblox map exceeds #{MAX_BYTES} bytes" if xml.bytesize > MAX_BYTES

      name = scene_ir.fetch("name").parameterize.presence || "roblox-scene"
      {
        "filename" => "#{name}.rbxlx",
        "media_type" => "application/xml",
        "encoding" => "base64",
        "data" => Base64.strict_encode64(xml),
        "byte_size" => xml.bytesize,
        "sha256" => Digest::SHA256.hexdigest(xml),
        "spec_digest" => scene_ir.fetch("spec_digest")
      }
    end
  end
end
