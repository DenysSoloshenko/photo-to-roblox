require "base64"
require "json"

module Vision
  class SceneAnalyzer
    class ConfigurationError < StandardError; end
    class ApiError < StandardError
      attr_reader :status, :request_id, :retry_after

      def initialize(message, status: nil, request_id: nil, retry_after: nil)
        super(message)
        @status, @request_id, @retry_after = status, request_id, retry_after
      end
    end
    class RateLimitError < ApiError; end
    class TimeoutError < ApiError; end

    DEFAULT_MODEL = "gpt-5.6-terra"
    DEFAULT_REASONING_EFFORT = "high"
    DEFAULT_REFINEMENT_REASONING_EFFORT = "medium"
    QUALITY_MODES = %w[terra astra_max].freeze
    ASTRA_RUN_LOCK = Mutex.new
    SUPPORTED_REASONING_EFFORTS = %w[none low medium high xhigh max].freeze
    SYSTEM_INSTRUCTIONS = "You are a spatial scene planner and final composition reviewer. Return only the strict structured SceneSpec; never return code, asset IDs, or prose."
    PROMPT_CACHE_KEY = "scene-foundry-v1-2"
    PRICING_LAST_VERIFIED = "2026-09-10"
    PRICES_PER_MILLION = {
      "gpt-5.6-terra" => { input: 2.0, cached_input: 0.2, output: 12.0 },
      "gpt-5.6-luna" => { input: 0.2, cached_input: 0.02, output: 1.2 },
      "gpt-4o-mini" => { input: 0.15, cached_input: 0.075, output: 0.6 },
      "gpt-6-astra" => { input: 10.0, cached_input: 1.0, cache_write: 12.5, output: 50.0 }
    }.freeze

    def self.for_quality(
      mode,
      api_key: ENV["OPENAI_API_KEY"],
      transport: nil,
      astra_enabled: ENV.fetch("ASTRA_QUALITY_ENABLED", "false") == "true"
    )
      quality_mode = mode.to_s.presence || "terra"
      raise ConfigurationError, "quality_mode must be one of: #{QUALITY_MODES.join(', ')}" unless QUALITY_MODES.include?(quality_mode)

      if quality_mode == "astra_max"
        raise ConfigurationError, "Astra Max is disabled; set ASTRA_QUALITY_ENABLED=true after configuring spend limits" unless astra_enabled

        new(
          api_key: api_key,
          model: "gpt-6-astra",
          reasoning_effort: "max",
          refinement_enabled: true,
          refinement_reasoning_effort: ENV.fetch("ASTRA_REFINEMENT_REASONING_EFFORT", "high"),
          quality_mode: quality_mode,
          transport: transport || HttpTransport.new(read_timeout: ENV.fetch("ASTRA_READ_TIMEOUT_SECONDS", "1200"))
        )
      else
        new(
          api_key: api_key,
          model: DEFAULT_MODEL,
          reasoning_effort: DEFAULT_REASONING_EFFORT,
          refinement_enabled: true,
          refinement_reasoning_effort: DEFAULT_REFINEMENT_REASONING_EFFORT,
          quality_mode: quality_mode,
          transport: transport || HttpTransport.new
        )
      end
    end

    def initialize(
      api_key: ENV["OPENAI_API_KEY"],
      model: ENV.fetch("VISION_MODEL", DEFAULT_MODEL),
      reasoning_effort: ENV.fetch("VISION_REASONING_EFFORT", DEFAULT_REASONING_EFFORT),
      refinement_enabled: ENV.fetch("VISION_REFINEMENT_ENABLED", "true") == "true",
      refinement_reasoning_effort: ENV.fetch("VISION_REFINEMENT_REASONING_EFFORT", DEFAULT_REFINEMENT_REASONING_EFFORT),
      quality_mode: nil,
      transport: HttpTransport.new
    )
      @api_key = api_key
      @model = model
      @reasoning_effort = reasoning_effort.to_s.strip
      @reasoning_effort = nil if @reasoning_effort.empty?
      @refinement_enabled = refinement_enabled
      @quality_mode = quality_mode || (@model == "gpt-6-astra" ? "astra_max" : "terra")
      @refinement_reasoning_effort = refinement_reasoning_effort.to_s.strip
      @refinement_reasoning_effort = nil if @refinement_reasoning_effort.empty?
      @transport = transport

      validate_effort!(@reasoning_effort, "VISION_REASONING_EFFORT")
      validate_effort!(@refinement_reasoning_effort, "VISION_REFINEMENT_REASONING_EFFORT")
      validate_model_effort!(@reasoning_effort, "VISION_REASONING_EFFORT")
      validate_model_effort!(@refinement_reasoning_effort, "VISION_REFINEMENT_REASONING_EFFORT")
    end

    def analyze(bytes:, mime_type:, filename:, hint: nil)
      raise ConfigurationError, "OPENAI_API_KEY is not configured" if @api_key.to_s.empty?
      astra_lock_acquired = false
      if @quality_mode == "astra_max"
        astra_lock_acquired = ASTRA_RUN_LOCK.try_lock
        raise ApiError, "another Astra Max generation is already running" unless astra_lock_acquired
      end

      draft = request_scene(request_payload(bytes: bytes, mime_type: mime_type, hint: hint))
      spec = draft.fetch(:scene_spec)
      refinement = if @refinement_enabled
        request_scene(refinement_payload(bytes: bytes, mime_type: mime_type, hint: hint, scene_spec: spec))
      end
      spec = refinement.fetch(:scene_spec) if refinement
      usage = merge_usage(draft.fetch(:usage), refinement&.fetch(:usage))
      draft_cost = calculate_cost(draft.fetch(:usage))
      refinement_cost = refinement ? calculate_cost(refinement.fetch(:usage)) : 0.0
      {
        scene_spec: spec,
        metrics: {
          "vision_model" => @model,
          "quality_mode" => @quality_mode,
          "reasoning_effort" => @reasoning_effort,
          "refinement_enabled" => !!refinement,
          "refinement_reasoning_effort" => refinement ? @refinement_reasoning_effort : nil,
          "draft_vision_ms" => draft.fetch(:elapsed_ms),
          "refinement_ms" => refinement&.fetch(:elapsed_ms),
          "vision_ms" => (draft.fetch(:elapsed_ms) + (refinement&.fetch(:elapsed_ms) || 0)).round(2),
          "input_tokens" => usage.fetch("input_tokens", 0),
          "cached_input_tokens" => usage.dig("input_tokens_details", "cached_tokens") || 0,
          "cache_write_tokens" => usage.dig("input_tokens_details", "cache_write_tokens") || 0,
          "output_tokens" => usage.fetch("output_tokens", 0),
          "draft_api_cost_usd" => draft_cost,
          "refinement_api_cost_usd" => refinement ? refinement_cost : nil,
          "api_cost_usd" => draft_cost && refinement_cost ? (draft_cost + refinement_cost).round(6) : nil,
          "provider_request_ids" => [draft[:request_id], refinement&.dig(:request_id)].compact,
          "provider_attempts" => draft.fetch(:attempts) + (refinement&.fetch(:attempts) || 0),
          "pricing_basis" => "OpenAI list pricing verified #{PRICING_LAST_VERIFIED}; image tokens are included in input_tokens"
        }
      }
    rescue JSON::ParserError => error
      raise ApiError, "vision response was not valid SceneSpec JSON: #{error.message}"
    ensure
      ASTRA_RUN_LOCK.unlock if astra_lock_acquired
    end

    private

    def request_payload(bytes:, mime_type:, hint:)
      schema = JSON.parse(Rails.root.join("config/schema/scene_spec.schema.json").read)
      build_payload(
        schema: schema,
        input: base_input(bytes: bytes, mime_type: mime_type, hint: hint),
        instructions: SYSTEM_INSTRUCTIONS,
        reasoning_effort: @reasoning_effort
      )
    end

    def base_prompt(hint)
      <<~PROMPT
        Build SceneSpec 1.1 from this real-location photograph. The deterministic builder, not the JSON, creates detail.

        Success means the Roblox camera reads like the photograph at first glance. Preserve the horizon, vanishing point,
        foreground/midground/background order, silhouettes, symmetry, open vistas, major paths, structures, water,
        vegetation masses, and elevation changes. Estimate scale in studs (1 stud is about 0.28 m). Approximate occluded
        areas conservatively and omit people and tiny objects.

        Build a compact game-scale diorama, not a survey-scale world. Keep the complete scene within roughly 300 x 300
        studs whenever possible and keep the recognizable foreground/midground composition large enough to play in.
        Compress distant water, shorelines, skylines, and mountains into scenic layers inside those bounds; never encode
        their real kilometre-scale distance or let a background layer force the foreground to be uniformly shrunk.

        First identify the scene family from visual evidence (for example yard, street, coast, park, garden, plaza,
        woodland, or mixed scene). Do not force a garden layout onto another scene. Use high-level patterns only when
        they match the photograph:
        - formal_garden creates radial or symmetrical petal beds, dense flowers, continuous stone borders, rings, and an arch;
        - terrace creates visible stepped elevation and retaining edges;
        - mountain_ridge creates a layered distant skyline;
        - forest_frame creates tall vegetation at both edges while preserving the central view.
        Patterns are procedural and much richer than manually listing repeated objects. Use at most four patterns.

        The representation is intentionally generic. Use ground/platform/ellipse/polygon/water surfaces for footprints,
        curved or straight paths for roads, paths, fences and shorelines, building for recognizable buildings, mass for
        any important solid without a dedicated component (such as a shed, pier, vehicle, wall, sculpture, or bridge),
        terrace for level changes, and groups for repeated vegetation. If an unfamiliar object is compositionally
        important, approximate its footprint, height, material, and orientation with these primitives instead of omitting it.

        Mark naturally curved paths with curve=true. Add all three border fields together or leave all three null.
        Use polygon surfaces only for important irregular footprints; polygon points are absolute world coordinates and
        polygon rotation_y must be zero. Use groups only for remaining repeated objects.

        Keep paths walkable, bases on their referenced surfaces, spawn on open dry ground, dimensions within the schema's
        documented limits, and the estimated result below 1,200 parts. Use at most 14 surfaces, 10 paths, 16 objects,
        10 groups, and 4 patterns. Set the camera from the photograph rather than choosing a generic aerial view.
        Optional user context: #{hint.to_s.strip.empty? ? "none" : hint.to_s.strip[0, 500]}
      PROMPT
    end

    def base_input(bytes:, mime_type:, hint:)
      [{
        role: "user",
        content: [
          { type: "input_text", text: base_prompt(hint) },
          { type: "input_image", image_url: "data:#{mime_type};base64,#{Base64.strict_encode64(bytes)}", detail: "high" }
        ]
      }]
    end

    def refinement_payload(bytes:, mime_type:, hint:, scene_spec:)
      schema = JSON.parse(Rails.root.join("config/schema/scene_spec.schema.json").read)
      review_prompt = <<~PROMPT
        Audit the draft SceneSpec against the photograph and return one complete corrected SceneSpec 1.1.
        Preserve correct draft decisions. Correct only material visual gaps: camera viewpoint, horizon and depth order,
        relative size and placement of composition anchors, symmetry, curved paths, open vistas, terrain levels, and use of
        procedural patterns. Confirm the pattern choices fit the actual scene family; remove any forced formal-garden
        pattern from a non-garden scene. Use mass objects for important unfamiliar solids. Prefer one strong matching
        pattern over many primitive objects. Do not duplicate geometry already owned by a procedural pattern. Treat the
        scene as a compact diorama: compress distant scenic layers instead of using real-world horizon distances, keep the
        main playable composition visually substantial, stay near 300 x 300 studs, and stay below 1,200 estimated parts.
        Do not add people, text, asset IDs, or imagined landmarks.
        Optional user context: #{hint.to_s.strip.empty? ? "none" : hint.to_s.strip[0, 500]}
        Draft SceneSpec: #{JSON.generate(scene_spec)}
      PROMPT
      build_payload(
        schema: schema,
        input: base_input(bytes: bytes, mime_type: mime_type, hint: hint) + [{
          role: "user",
          content: [{ type: "input_text", text: review_prompt }]
        }],
        instructions: SYSTEM_INSTRUCTIONS,
        reasoning_effort: @refinement_reasoning_effort
      )
    end

    def build_payload(schema:, input:, instructions:, reasoning_effort:)
      payload = {
        model: @model,
        store: false,
        instructions: instructions,
        input: input,
        text: { format: { type: "json_schema", name: "scene_spec", strict: true, schema: schema } },
        max_output_tokens: max_output_tokens,
        prompt_cache_key: PROMPT_CACHE_KEY,
        prompt_cache_options: { ttl: "30m" }
      }

      payload[:reasoning] = { effort: reasoning_effort } if reasoning_effort
      payload
    end

    def max_output_tokens
      if @model == "gpt-6-astra"
        ENV.fetch("ASTRA_MAX_OUTPUT_TOKENS", "48000").to_i
      else
        ENV.fetch("VISION_MAX_OUTPUT_TOKENS", "10000").to_i
      end
    end

    def request_scene(payload)
      started_at = monotonic_time
      response = @transport.post(
        url: "https://api.openai.com/v1/responses",
        headers: { "Authorization" => "Bearer #{@api_key}", "Content-Type" => "application/json" },
        body: JSON.generate(payload)
      )
      scene_spec = JSON.parse(extract_output_text(response))
      raise ApiError, "vision output must be a SceneSpec object" unless scene_spec.is_a?(Hash)

      {
        scene_spec: scene_spec,
        usage: response["usage"].is_a?(Hash) ? response["usage"] : {},
        request_id: response.dig("_transport", "request_id"),
        attempts: response.dig("_transport", "attempts") || 1,
        elapsed_ms: ((monotonic_time - started_at) * 1000).round(2)
      }
    end

    def merge_usage(first, second)
      usages = [first, second].compact
      {
        "input_tokens" => usages.sum { |usage| usage.fetch("input_tokens", 0).to_i },
        "input_tokens_details" => {
          "cached_tokens" => usages.sum { |usage| (usage.dig("input_tokens_details", "cached_tokens") || 0).to_i },
          "cache_write_tokens" => usages.sum { |usage| (usage.dig("input_tokens_details", "cache_write_tokens") || 0).to_i }
        },
        "output_tokens" => usages.sum { |usage| usage.fetch("output_tokens", 0).to_i }
      }
    end

    def validate_effort!(value, variable_name)
      return unless value && !SUPPORTED_REASONING_EFFORTS.include?(value)

      raise ConfigurationError, "#{variable_name} must be one of: #{SUPPORTED_REASONING_EFFORTS.join(', ')}"
    end

    def validate_model_effort!(value, variable_name)
      return unless @model == "gpt-6-astra" && value == "none"

      raise ConfigurationError, "#{variable_name}=none is not supported by gpt-6-astra"
    end

    def extract_output_text(response)
      unless response["status"] == "completed"
        reason = response.dig("incomplete_details", "reason") || response.dig("error", "message") || response["status"] || "unknown"
        raise ApiError, "vision response did not complete: #{reason}"
      end

      output = response["output"]
      raise ApiError, "vision response did not contain an output array" unless output.is_a?(Array)

      output.each do |item|
        next unless item.is_a?(Hash) && item["type"] == "message" && item["content"].is_a?(Array)

        item["content"].each do |content|
          next unless content.is_a?(Hash)
          return content["text"] if content["type"] == "output_text" && content["text"].is_a?(String)
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
