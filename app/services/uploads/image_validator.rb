module Uploads
  class ImageValidator
    TYPES = %w[image/jpeg image/png image/webp].freeze
    MAX_BYTES = 10.megabytes

    def self.errors(upload)
      return ["Upload an image file"] unless upload.respond_to?(:tempfile) && upload.respond_to?(:content_type)
      return ["Image must be between 1 byte and 10 MB"] unless upload.size.between?(1, MAX_BYTES)
      detected = Marcel::MimeType.for(upload.tempfile)
      unless TYPES.include?(detected) && detected == upload.content_type
        return ["Image contents must match JPEG, PNG, or WebP"]
      end
      []
    ensure
      upload.rewind if upload.respond_to?(:rewind)
    end
  end
end
