require "test_helper"

class VisionSceneAnalyzerTest < ActiveSupport::TestCase
  class FakeTransport
    attr_reader :request

    def initialize(scene_spec, usage: nil)
      @scene_spec = scene_spec
      @usage = usage || { "input_tokens" => 1_000, "input_tokens_details" => { "cached_tokens" => 100 }, "output_tokens" => 500 }
    end

    def post(**request)
      @request = request
      {
        "output" => [{ "type" => "message", "content" => [{ "type" => "output_text", "text" => JSON.generate(@scene_spec) }] }],
        "usage" => @usage
      }
    end
  end

  test "sends supported reasoning effort and prices Astra cache writes" do
    spec = JSON.parse(Rails.root.join("examples/park.json").read)
    usage = {
      "input_tokens" => 1_000,
      "input_tokens_details" => { "cached_tokens" => 100, "cache_write_tokens" => 200 },
      "output_tokens" => 500
    }
    transport = FakeTransport.new(spec, usage: usage)

    result = Vision::SceneAnalyzer.new(
      api_key: "test-key",
      model: "gpt-6-astra",
      reasoning_effort: "high",
      transport: transport
    ).analyze(bytes: "image", mime_type: "image/png", filename: "garden.png")
    payload = JSON.parse(transport.request.fetch(:body))

    assert_equal "high", payload.dig("reasoning", "effort")
    assert_equal 24_000, payload.fetch("max_output_tokens")
    assert_equal "high", result.dig(:metrics, "reasoning_effort")
    assert_equal 200, result.dig(:metrics, "cache_write_tokens")
    assert_equal 0.0346, result.dig(:metrics, "api_cost_usd")
  end

  test "rejects an unsupported reasoning effort" do
    error = assert_raises(Vision::SceneAnalyzer::ConfigurationError) do
      Vision::SceneAnalyzer.new(api_key: "test-key", reasoning_effort: "ultra")
    end

    assert_match(/must be one of/, error.message)
  end

  test "sends photo as structured vision request and records cost" do
    spec = JSON.parse(Rails.root.join("examples/park.json").read)
    transport = FakeTransport.new(spec)
    result = Vision::SceneAnalyzer.new(api_key: "test-key", model: "gpt-5.6-terra", transport: transport).analyze(
      bytes: "fake-image-bytes", mime_type: "image/jpeg", filename: "yard.jpg", hint: "Back garden"
    )
    payload = JSON.parse(transport.request.fetch(:body))

    assert_equal "gpt-5.6-terra", payload.fetch("model")
    assert_equal false, payload.fetch("store")
    assert_equal "json_schema", payload.dig("text", "format", "type")
    assert_equal true, payload.dig("text", "format", "strict")
    refute_match(/(?:minimum|maximum|minLength|maxLength|minItems|maxItems|pattern)/, JSON.generate(payload.dig("text", "format", "schema")))
    assert_match(%r{\Adata:image/jpeg;base64,}, payload.dig("input", 0, "content", 1, "image_url"))
    assert_match(/below\s+1,200 estimated parts/, payload.dig("input", 0, "content", 0, "text"))
    assert_equal spec, result.fetch(:scene_spec)
    assert_equal 0.00782, result.dig(:metrics, "api_cost_usd")
    assert_equal "yard.jpg", result.dig(:metrics, "source_filename")
  end

  test "requires an API key" do
    error = assert_raises(Vision::SceneAnalyzer::ConfigurationError) do
      Vision::SceneAnalyzer.new(api_key: "").analyze(bytes: "x", mime_type: "image/png", filename: "x.png")
    end
    assert_equal "OPENAI_API_KEY is not configured", error.message
  end
end
