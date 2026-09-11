require "test_helper"

class VisionSceneAnalyzerTest < ActiveSupport::TestCase
  class FakeTransport
    attr_reader :request

    def initialize(scene_spec)
      @scene_spec = scene_spec
    end

    def post(**request)
      @request = request
      {
        "output" => [{ "type" => "message", "content" => [{ "type" => "output_text", "text" => JSON.generate(@scene_spec) }] }],
        "usage" => { "input_tokens" => 1_000, "input_tokens_details" => { "cached_tokens" => 100 }, "output_tokens" => 500 }
      }
    end
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
