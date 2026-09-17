require "test_helper"

class VisionHttpTransportTest < ActiveSupport::TestCase
  def response(status, body, headers = {})
    object = Net::HTTPResponse::CODE_TO_OBJ.fetch(status.to_s).new("1.1", status.to_s, "test")
    headers.each { |key, value| object[key] = value }
    object.define_singleton_method(:read_body) { |&block| Array(body).each(&block) }
    object
  end

  def with_responses(responses)
    @requests = []
    @options = []
    http = Object.new
    requests = @requests
    http.define_singleton_method(:request) do |request, &block|
      requests << request
      next_response = responses.shift
      raise next_response if next_response.is_a?(Exception)
      raise "unexpected duplicate request" unless next_response
      block.call(next_response)
    end
    start = ->(*_args, **options, &block) { @options << options; block.call(http) }
    Net::HTTP.stub(:start, start) { yield }
  end

  def post(transport = Vision::HttpTransport.new(sleeper: ->(_) {}))
    transport.post(url: "https://api.openai.com/v1/responses", headers: { "Authorization" => "Bearer secret" }, body: "{}")
  end

  test "respects rate limit delays and reports request IDs and attempts" do
    sleeps = []
    transport = Vision::HttpTransport.new(sleeper: ->(seconds) { sleeps << seconds })
    with_responses([
      response(429, '{"error":{"code":"rate_limit_exceeded"}}', "Retry-After" => "2"),
      response(200, '{"status":"completed"}', "X-Request-Id" => "req_123")
    ]) do
      result = post(transport)
      assert_equal [2.0], sleeps
      assert_equal({ "request_id" => "req_123", "attempts" => 2 }, result["_transport"])
      assert_equal 0, @options.first[:max_retries]
      assert_equal 30, @options.first[:write_timeout]
      assert_equal 2, @requests.map { |request| request["X-Client-Request-Id"] }.uniq.length
    end
  end

  test "quota exhaustion and long retry delays are not retried" do
    [response(429, '{"error":{"code":"insufficient_quota"}}'),
     response(429, '{}', "Retry-After" => "120")].each do |upstream|
      with_responses([upstream]) do
        assert_raises(Vision::SceneAnalyzer::RateLimitError) { post }
        assert_equal 1, @requests.size
      end
    end
  end

  test "handles HTML gateway failures and stops after two retries" do
    with_responses(Array.new(3) { response(502, "<h1>Bad gateway</h1>") }) do
      error = assert_raises(Vision::SceneAnalyzer::ApiError) { post }
      assert_equal 502, error.status
      assert_equal 3, @requests.size
      refute_includes error.message, "<h1>"
    end
  end

  test "does not repeat a POST after an ambiguous connection failure or timeout" do
    [Net::ReadTimeout.new, Net::WriteTimeout.new, EOFError.new].each do |failure|
      with_responses([failure]) do
        error = assert_raises(Vision::SceneAnalyzer::ApiError) { post }
        assert_includes error.message, "not automatically repeated"
        assert_equal 1, @requests.size
      end
    end
  end

  test "invalid or non-object success bodies become API errors" do
    ["", "[]", "null", "<html>oops</html>"].each do |body|
      with_responses([response(200, body)]) do
        assert_raises(Vision::SceneAnalyzer::ApiError) { post }
        assert_equal 1, @requests.size
      end
    end
  end

  test "limits streamed response size" do
    with_responses([response(200, ["x" * Vision::HttpTransport::MAX_RESPONSE_BYTES, "x"])]) do
      error = assert_raises(Vision::SceneAnalyzer::ApiError) { post }
      assert_includes error.message, "5 MB"
    end
  end

  test "never reflects an upstream credential error body" do
    with_responses([response(401, '{"error":{"message":"secret key sk-private"}}', "X-Request-Id" => "req_auth")]) do
      error = assert_raises(Vision::SceneAnalyzer::ApiError) { post }
      assert_equal "req_auth", error.request_id
      refute_includes error.message, "sk-private"
      assert_equal 1, @requests.size
    end
  end

  test "rejects unsafe timeout configuration" do
    [0, -1, "oops", "NaN", 1801].each do |value|
      assert_raises(Vision::SceneAnalyzer::ConfigurationError) { Vision::HttpTransport.new(read_timeout: value) }
    end
  end
  test "retries share one time budget" do
    transport = Vision::HttpTransport.new(read_timeout: 0.1, sleeper: ->(_) { flunk "should not sleep beyond the deadline" })
    with_responses([response(429, "{}", "Retry-After" => "2")]) do
      assert_raises(Vision::SceneAnalyzer::TimeoutError) { post(transport) }
      assert_equal 1, @requests.size
    end
  end

end
