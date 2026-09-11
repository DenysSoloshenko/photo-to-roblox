require "base64"
require "json"

module Vision
  class SceneAnalyzer
    class ConfigurationError < StandardError; end
    class ApiError < StandardError; end

    DEFAULT_MODEL = "gpt-5.6-terra"
    PRICES_PER_MILLION = {
      "gpt-5.6-terra" => { input: 2.0, cached_input: 0.2, output: 12.0 },
      "gpt-5.6-luna" => { input: 0.2, cached_input: 0.02, output: 1.2 },
      "gpt-4o-mini" => { input: 0.15, cached_input: 0.075, output: 0.6 }
    }.freeze

    def initialize(api_key: ENV["OPENAI_API_KEY"], model: ENV.fetch("VISION_MODEL", DEFAULT_MODEL), transport: HttpTransport.new)
      @api_key = api_key
      @model = model
      @transport = transport
    end

    def analyze(bytes:, mime_type:, filename:, hint: nil)
      raise ConfigurationError, "OPENAI_API_KEY is not configured" if @api_key.to_s.empty?

      started_at = monotonic_time
      response = @transport.post(
        url: "https://api.openai.com/v1/responses",
        headers: { "Authorization" => "Bearer #{@api_key}", "Content-Type" => "application/json" },
        body: JSON.generate(request_payload(bytes: bytes, mime_type: mime_type, hint: hint))
      )
      elapsed_ms = ((monotonic_time - started_at) * 1000).round(2)
      output_text = extract_output_text(response)
      spec = JSON.parse(output_text)
      usage = response.fetch("usage", {})
      {
        scene_spec: spec,
        metrics: {
          "vision_model" => @model,
          "vision_ms" => elapsed_ms,
          "input_tokens" => usage.fetch("input_tokens", 0),
          "cached_input_tokens" => usage.dig("input_tokens_details", "cached_tokens") || 0,
          "output_tokens" => usage.fetch("output_tokens", 0),
          "api_cost_usd" => calculate_cost(usage),
          "pricing_basis" => "per-token estimate from model pricing; image tokens are included in input_tokens",
          "source_filename" => filename
        }
      }
    rescue JSON::ParserError => error
      raise ApiError, "vision response was not valid SceneSpec JSON: #{error.message}"
    end

    private

    def request_payload(bytes:, mime_type:, hint:)
      schema = JSON.parse(Rails.root.join("config/schema/scene_spec.schema.json").read)
      prompt = <<~PROMPT
        Convert this single real-location photograph into a compact SceneSpec for a deterministic Roblox scene builder.
        Preserve the recognizable composition: camera-facing arrangement of major buildings, paths, vegetation, water,
        boundaries, and visible elevation changes. Estimate scale in Roblox studs (1 stud is approximately 0.28 m).
        Approximate unseen areas conservatively; do not invent landmarks. Use explicit objects for composition-defining
        features and compact groups only for repeated vegetation or rocks. Keep paths walkable, put object bases on their
        referenced surfaces, and place the spawn on dry open ground outside buildings. Use only schema-listed component
        types and materials. The camera must reproduce the photograph's main viewpoint.
        Optional user context: #{hint.to_s.strip.empty? ? "none" : hint.to_s.strip[0, 500]}
      PROMPT
      {
        model: @model,
        store: false,
        instructions: "You are a spatial scene analyst. Return only the strict structured SceneSpec; never return code, scripts, asset IDs, or prose.",
        input: [{
          role: "user",
          content: [
            { type: "input_text", text: prompt },
            { type: "input_image", image_url: "data:#{mime_type};base64,#{Base64.strict_encode64(bytes)}", detail: "high" }
          ]
        }],
        text: { format: { type: "json_schema", name: "scene_spec", strict: true, schema: schema } },
        max_output_tokens: 8_000
      }
    end

    def extract_output_text(response)
      response.fetch("output", []).each do |item|
        next unless item["type"] == "message"

        item.fetch("content", []).each do |content|
          return content.fetch("text") if content["type"] == "output_text"
          raise ApiError, content.fetch("refusal", "vision request was refused") if content["type"] == "refusal"
        end
      end
      raise ApiError, response.dig("error", "message") || "vision response did not contain structured output"
    end

    def calculate_cost(usage)
      pricing = PRICES_PER_MILLION[@model]
      return nil unless pricing

      input = usage.fetch("input_tokens", 0).to_i
      cached = (usage.dig("input_tokens_details", "cached_tokens") || 0).to_i
      output = usage.fetch("output_tokens", 0).to_i
      cost = ((input - cached) * pricing[:input] + cached * pricing[:cached_input] + output * pricing[:output]) / 1_000_000.0
      cost.round(6)
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
