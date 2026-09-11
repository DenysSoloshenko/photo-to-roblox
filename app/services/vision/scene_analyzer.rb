require "base64"
require "json"

module Vision
  class SceneAnalyzer
    class ConfigurationError < StandardError; end
    class ApiError < StandardError; end

    DEFAULT_MODEL = "gpt-5.6-terra"
    SUPPORTED_REASONING_EFFORTS = %w[low medium high xhigh max].freeze
    PRICING_LAST_VERIFIED = "2026-09-10"
    PRICES_PER_MILLION = {
      "gpt-5.6-terra" => { input: 2.0, cached_input: 0.2, output: 12.0 },
      "gpt-5.6-luna" => { input: 0.2, cached_input: 0.02, output: 1.2 },
      "gpt-4o-mini" => { input: 0.15, cached_input: 0.075, output: 0.6 },
      "gpt-6-astra" => { input: 10.0, cached_input: 1.0, cache_write: 12.5, output: 50.0 }
    }.freeze

    def initialize(
      api_key: ENV["OPENAI_API_KEY"],
      model: ENV.fetch("VISION_MODEL", DEFAULT_MODEL),
      reasoning_effort: ENV["VISION_REASONING_EFFORT"],
      transport: HttpTransport.new
    )
      @api_key = api_key
      @model = model
      @reasoning_effort = reasoning_effort.to_s.strip
      @reasoning_effort = nil if @reasoning_effort.empty?
      @transport = transport

      if @reasoning_effort && !SUPPORTED_REASONING_EFFORTS.include?(@reasoning_effort)
        raise ConfigurationError, "VISION_REASONING_EFFORT must be one of: #{SUPPORTED_REASONING_EFFORTS.join(', ')}"
      end
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
          "reasoning_effort" => @reasoning_effort,
          "vision_ms" => elapsed_ms,
          "input_tokens" => usage.fetch("input_tokens", 0),
          "cached_input_tokens" => usage.dig("input_tokens_details", "cached_tokens") || 0,
          "cache_write_tokens" => usage.dig("input_tokens_details", "cache_write_tokens") || 0,
          "output_tokens" => usage.fetch("output_tokens", 0),
          "api_cost_usd" => calculate_cost(usage),
          "pricing_basis" => "OpenAI list pricing verified #{PRICING_LAST_VERIFIED}; image tokens are included in input_tokens",
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
        types and materials. Keep bounds width/depth between 20 and 500 studs, bounds max_height between 5 and 500,
        and every numeric component dimension between 0.01 and 200 studs. The camera must reproduce the photograph's
        main viewpoint. Keep the complete scene below
        1,200 estimated parts. Estimate each surface as 1 part and a path with N points as 2N-1 parts; each tree as 5,
        bush as 4, flower as 5, hedge as 1, conifer as 5, arch as 27, mountain as 3, rock as 1, bench as 7,
        fence as 32, and building as 10. A repeated group costs its count multiplied by its component estimate.
        Prefer a few well-placed repeated objects over dense groups so the scene remains safely below the budget.
        Keep the JSON compact and complete: use at most 18 surfaces, 12 paths, 20 individual objects, and 12 groups.
        For gardens, use ellipse surfaces for circular or curved beds, flower groups with flower_mix or flower colors for
        visible blooms, hedge objects or groups for clipped borders, arch for arbors, and conifer for pointed evergreens.
        Use mountain objects only for large distant silhouette masses. Alternate flower_red, flower_orange, flower_pink,
        flower_yellow, flower_purple, and flower_white across major beds. Do not represent flowers as ordinary bushes.
        When water or mountains form the background, use distribution frame for tall tree and conifer groups so vegetation
        clusters at the left and right edges and does not block the central vista. Keep distant water visibly wide.
        Do not spend output on people or tiny details; preserve the large-scale symmetry, terraces, paths, tree line,
        water, skyline, and other composition anchors. The response must end with a complete valid JSON object.
        Optional user context: #{hint.to_s.strip.empty? ? "none" : hint.to_s.strip[0, 500]}
      PROMPT
      payload = {
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
        max_output_tokens: ENV.fetch("VISION_MAX_OUTPUT_TOKENS", @model == "gpt-6-astra" ? "24000" : "8000").to_i
      }

      payload[:reasoning] = { effort: @reasoning_effort } if @reasoning_effort
      payload
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
      cache_write = (usage.dig("input_tokens_details", "cache_write_tokens") || 0).to_i
      output = usage.fetch("output_tokens", 0).to_i
      uncached = [input - cached - cache_write, 0].max
      cache_write_price = pricing.fetch(:cache_write, pricing.fetch(:input))
      cost = (uncached * pricing[:input] + cached * pricing[:cached_input] + cache_write * cache_write_price + output * pricing[:output]) / 1_000_000.0
      cost.round(6)
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
