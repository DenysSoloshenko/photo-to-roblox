require "net/http"
require "uri"

module Vision
  class HttpTransport
    def post(url:, headers:, body:)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      headers.each { |name, value| request[name] = value }
      request.body = body
      read_timeout = ENV.fetch("VISION_READ_TIMEOUT_SECONDS", "300").to_i
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: read_timeout) { |http| http.request(request) }
      parsed = JSON.parse(response.body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      message = parsed.dig("error", "message") || "OpenAI API returned HTTP #{response.code}"
      raise SceneAnalyzer::ApiError, message
    rescue JSON::ParserError
      raise SceneAnalyzer::ApiError, "OpenAI API returned an invalid JSON response"
    end
  end
end
