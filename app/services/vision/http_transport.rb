require "net/http"
require "uri"
require "json"
require "time"
require "securerandom"

module Vision
  class HttpTransport
    RETRYABLE_STATUSES = [408, 409, 429, 500, 502, 503, 504].freeze
    MAX_RESPONSE_BYTES = 5 * 1024 * 1024
    MAX_RETRY_DELAY = 30

    def initialize(read_timeout: nil, max_retries: ENV.fetch("VISION_MAX_RETRIES", "2"), sleeper: ->(seconds) { sleep(seconds) })
      @read_timeout = positive_timeout(read_timeout || ENV.fetch("VISION_READ_TIMEOUT_SECONDS", "300"))
      @max_retries = Integer(max_retries).clamp(0, 2)
      @sleeper = sleeper
    rescue ArgumentError, TypeError
      raise SceneAnalyzer::ConfigurationError, "Vision timeout must be positive and VISION_MAX_RETRIES must be an integer"
    end

    def post(url:, headers:, body:)
      uri = URI(url)
      raise SceneAnalyzer::ConfigurationError, "Vision endpoint must use HTTPS" unless uri.is_a?(URI::HTTPS)

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @read_timeout
      attempt = 0
      loop do
        request = Net::HTTP::Post.new(uri)
        headers.each { |name, value| request[name] = value }
        request["X-Client-Request-Id"] = SecureRandom.uuid
        request.body = body
        response, raw_body = perform(uri, request, deadline)
        status = response.code.to_i
        request_id = response["x-request-id"]
        parsed = parse_body(raw_body)
        if response.is_a?(Net::HTTPSuccess)
          raise SceneAnalyzer::ApiError, "OpenAI API returned an invalid JSON object" unless parsed.is_a?(Hash)

          return parsed.merge("_transport" => { "request_id" => request_id, "attempts" => attempt + 1 })
        end

        error_data = parsed.is_a?(Hash) && parsed["error"].is_a?(Hash) ? parsed["error"] : {}
        code = error_data["code"]
        delay = retry_delay(response, attempt)
        retryable = RETRYABLE_STATUSES.include?(status) && code != "insufficient_quota"
        if retryable && attempt < @max_retries && delay
          Rails.logger.warn({ event: "vision_request_retry", status: status, request_id: request_id, attempt: attempt + 1, delay_seconds: delay }.to_json)
          raise Net::ReadTimeout if Process.clock_gettime(Process::CLOCK_MONOTONIC) + delay >= deadline

          @sleeper.call(delay)
          attempt += 1
          next
        end

        message = case status
                  when 401, 403 then "OpenAI API credentials or model access were rejected"
                  when 429 then code == "insufficient_quota" ? "OpenAI API quota is exhausted; check project billing" : "OpenAI API rate limit reached; try again later"
                  else "OpenAI API returned HTTP #{status}"
                  end
        error_class = status == 429 ? SceneAnalyzer::RateLimitError : SceneAnalyzer::ApiError
        raise error_class.new(message, status: status, request_id: request_id, retry_after: retry_after(response))
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
      # A timed-out POST may already have been accepted and billed upstream.
      raise SceneAnalyzer::TimeoutError, "OpenAI API timed out; the request was not automatically repeated"
    rescue SocketError, OpenSSL::SSL::SSLError, EOFError, IOError, SystemCallError => error
      raise SceneAnalyzer::ApiError, "OpenAI API connection failed: #{error.class.name}; the request was not automatically repeated"
    end

    private

    def perform(uri, request, deadline)
      body = +""
      response = nil
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raise Net::ReadTimeout unless remaining.positive?
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10,
        read_timeout: remaining, write_timeout: [30, remaining].min, max_retries: 0) do |http|
        http.request(request) do |upstream|
          response = upstream
          upstream.read_body do |chunk|
            raise SceneAnalyzer::ApiError, "OpenAI API response exceeds the 5 MB limit" if body.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES
            raise Net::ReadTimeout if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

            body << chunk
          end
        end
      end
      [response, body]
    end

    def parse_body(body)
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def retry_after(response)
      value = response["retry-after"]
      return nil unless value

      seconds = Float(value, exception: false)
      seconds ||= Time.httpdate(value) - Time.now
      seconds.finite? && seconds >= 0 ? seconds : nil
    rescue ArgumentError
      nil
    end

    def retry_delay(response, attempt)
      delay = retry_after(response)
      return nil if delay && delay > MAX_RETRY_DELAY

      delay || (0.5 * (2**attempt) * (0.75 + rand * 0.25))
    end

    def positive_timeout(value)
      timeout = Float(value)
      raise ArgumentError unless timeout.finite? && timeout.positive? && timeout <= 1_800

      timeout
    end
  end
end
