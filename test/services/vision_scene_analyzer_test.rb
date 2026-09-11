require "test_helper"

class VisionSceneAnalyzerTest < ActiveSupport::TestCase
  class FakeTransport
    attr_reader :requests

    def initialize(scene_spec, usage: nil)
      @scene_spec = scene_spec
      @usage = usage || { "input_tokens" => 1_000, "input_tokens_details" => { "cached_tokens" => 100 }, "output_tokens" => 500 }
      @requests = []
    end

    def post(**request)
      @requests << request
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
      refinement_enabled: false,
      transport: transport
    ).analyze(bytes: "image", mime_type: "image/png", filename: "garden.png")
    payload = JSON.parse(transport.requests.first.fetch(:body))

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
    result = Vision::SceneAnalyzer.new(api_key: "test-key", model: "gpt-5.6-terra", refinement_enabled: false, transport: transport).analyze(
      bytes: "fake-image-bytes", mime_type: "image/jpeg", filename: "yard.jpg", hint: "Back garden"
    )
    payload = JSON.parse(transport.requests.first.fetch(:body))

    assert_equal "gpt-5.6-terra", payload.fetch("model")
    assert_equal false, payload.fetch("store")
    assert_equal "json_schema", payload.dig("text", "format", "type")
    assert_equal true, payload.dig("text", "format", "strict")
    refute_match(/"(?:minimum|maximum|minLength|maxLength|minItems|maxItems)"\s*:/, JSON.generate(payload.dig("text", "format", "schema")))
    assert_match(%r{\Adata:image/jpeg;base64,}, payload.dig("input", 0, "content", 1, "image_url"))
    assert_match(/below 1,200 parts/, payload.dig("input", 0, "content", 0, "text"))
    assert_equal spec, result.fetch(:scene_spec)
    assert_equal 0.00782, result.dig(:metrics, "api_cost_usd")
    assert_equal "yard.jpg", result.dig(:metrics, "source_filename")
  end

  test "runs a cheaper composition refinement after the high-reasoning draft" do
    spec = JSON.parse(Rails.root.join("examples/coast.json").read)
    transport = FakeTransport.new(spec)

    result = Vision::SceneAnalyzer.new(
      api_key: "test-key", model: "gpt-5.6-terra", reasoning_effort: "high",
      refinement_enabled: true, refinement_reasoning_effort: "medium", transport: transport
    ).analyze(bytes: "image", mime_type: "image/png", filename: "coast.png")

    assert_equal 2, transport.requests.length
    draft_payload = JSON.parse(transport.requests.first.fetch(:body))
    review_payload = JSON.parse(transport.requests.second.fetch(:body))
    assert_equal "high", draft_payload.dig("reasoning", "effort")
    assert_equal "medium", review_payload.dig("reasoning", "effort")
    assert_equal draft_payload.fetch("instructions"), review_payload.fetch("instructions")
    assert_equal draft_payload.dig("input", 0), review_payload.dig("input", 0)
    assert_equal draft_payload.fetch("prompt_cache_key"), review_payload.fetch("prompt_cache_key")
    assert_equal 2, review_payload.fetch("input").length
    assert result.dig(:metrics, "refinement_enabled")
    assert_equal 2_000, result.dig(:metrics, "input_tokens")
    assert_equal 0.01564, result.dig(:metrics, "api_cost_usd")
  end

  test "requires an API key" do
    error = assert_raises(Vision::SceneAnalyzer::ConfigurationError) do
      Vision::SceneAnalyzer.new(api_key: "").analyze(bytes: "x", mime_type: "image/png", filename: "x.png")
    end
    assert_equal "OPENAI_API_KEY is not configured", error.message
  end
end
