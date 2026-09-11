require "net/http"
require "uri"

module Vision
  class HttpTransport
    def initialize(read_timeout: nil)
      @read_timeout = read_timeout
    end

    def post(url:, headers:, body:)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      headers.each { |name, value| request[name] = value }
      request.body = body
      read_timeout = @read_timeout || ENV.fetch("VISION_READ_TIMEOUT_SECONDS", "300").to_i
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: read_timeout) { |http| http.request(request) }
      parsed = JSON.parse(response.body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      message = parsed.dig("error", "message") || "OpenAI API returned HTTP #{response.code}"
      raise SceneAnalyzer::ApiError, message
    rescue JSON::ParserError
      raise SceneAnalyzer::ApiError, "OpenAI API returned an invalid JSON response"
    rescue Net::OpenTimeout, Net::ReadTimeout
      raise SceneAnalyzer::TimeoutError, "OpenAI API timed out before the vision response completed"
    rescue SocketError, OpenSSL::SSL::SSLError, EOFError, Errno::ECONNRESET, Errno::ECONNREFUSED => error
      raise SceneAnalyzer::ApiError, "OpenAI API connection failed: #{error.class.name}"
    end
  end
end
