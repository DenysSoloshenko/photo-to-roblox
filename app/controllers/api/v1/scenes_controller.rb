module Api
  module V1
    class ScenesController < ApplicationController
      MAX_UPLOAD_BYTES = 10 * 1024 * 1024
      ALLOWED_TYPES = %w[image/jpeg image/png image/webp].freeze

      before_action :authenticate_user!
      before_action :require_admin!
      before_action :protect_api!, only: %i[analyze compile export]

      rescue_from Roblox::MapArtifact::TooLarge do |error|
        render json: { error: "map_too_large", message: error.message }, status: :payload_too_large
      end

      def status
        render json: {
          ok: true,
          vision_configured: ENV["OPENAI_API_KEY"].present?,
          vision_model: Vision::SceneAnalyzer::DEFAULT_MODEL,
          vision_reasoning_effort: Vision::SceneAnalyzer::DEFAULT_REASONING_EFFORT,
          vision_refinement_enabled: true,
          vision_refinement_reasoning_effort: Vision::SceneAnalyzer::DEFAULT_REFINEMENT_REASONING_EFFORT,
          quality_modes: Vision::SceneAnalyzer::QUALITY_MODES,
          default_quality_mode: "terra",
          astra_quality_enabled: ENV.fetch("ASTRA_QUALITY_ENABLED", "false") == "true",
          development_examples_enabled: Rails.env.development? || Rails.env.test?,
          component_version: Scene::Compiler::COMPONENT_VERSION
        }
      end

      def schema
        render json: JSON.parse(Rails.root.join("config/schema/scene_spec.schema.json").read)
      end

      def example
        return head :not_found unless Rails.env.development? || Rails.env.test?

        name = params[:name].to_s
        return head :not_found unless %w[park courtyard coast garden].include?(name)

        scene_spec = JSON.parse(Rails.root.join("examples/#{name}.json").read)
        scene_ir = Scene::Compiler.new.compile_scene(scene_spec)
        render json: scene_payload(scene_spec, scene_ir, { "compile_ms" => scene_ir.dig("stats", "compile_ms") }, include_map: include_map?)
      end

      def analyze
        started_at = monotonic_time
        upload = params[:photo]
        return render_error("$.photo", "is required", :unprocessable_entity) unless upload.respond_to?(:read)
        return render_error("$.photo", "must be JPEG, PNG, or WebP", :unsupported_media_type) unless ALLOWED_TYPES.include?(upload.content_type)
        return render_error("$.photo", "must be 10 MB or smaller", :payload_too_large) if upload.size > MAX_UPLOAD_BYTES
        quality_mode = params[:quality_mode].presence || "terra"
        unless Vision::SceneAnalyzer::QUALITY_MODES.include?(quality_mode)
          return render_error("$.quality_mode", "must be one of #{Vision::SceneAnalyzer::QUALITY_MODES.join(', ')}", :unprocessable_entity)
        end

        analysis = Vision::SceneAnalyzer.for_quality(quality_mode).analyze(
          bytes: upload.read,
          mime_type: upload.content_type,
          filename: upload.original_filename,
          hint: params[:hint]
        )
        geometry = Scene::GeometryNormalizer.new(analysis.fetch(:scene_spec)).normalize
        budget = Scene::BudgetNormalizer.new(geometry.fetch(:scene_spec)).normalize
        scene_spec = budget.fetch(:scene_spec)
        scene_ir = Scene::Compiler.new.compile_scene(scene_spec)
        metrics = analysis.fetch(:metrics).merge(geometry.fetch(:metrics)).merge(budget.fetch(:metrics)).merge(
          "compile_ms" => scene_ir.dig("stats", "compile_ms"),
          "order_id" => request.request_id
        )
        payload = scene_payload(scene_spec, scene_ir, metrics, include_map: include_map?)
        payload.fetch(:metrics)["total_ms"] = ((monotonic_time - started_at) * 1000).round(2)
        Rails.logger.info({ event: "scene_order_completed", order_id: request.request_id, metrics: payload.fetch(:metrics) }.to_json)
        render json: payload
      rescue Vision::SceneAnalyzer::ConfigurationError => error
        render json: { error: "vision_not_configured", message: error.message }, status: :service_unavailable
      rescue Vision::SceneAnalyzer::TimeoutError => error
        render json: { error: "vision_timeout", message: error.message }, status: :gateway_timeout
      rescue Vision::SceneAnalyzer::RateLimitError => error
        response.headers["Retry-After"] = error.retry_after.ceil.to_s if error.retry_after
        render json: { error: "vision_rate_limited", message: error.message, request_id: error.request_id }, status: :too_many_requests
      rescue Vision::SceneAnalyzer::ApiError => error
        render json: { error: "vision_api_error", message: error.message, request_id: error.request_id }, status: :bad_gateway
      rescue Scene::ValidationError => error
        render json: { error: "invalid_scene_spec", errors: error.errors }, status: :unprocessable_entity
      end

      def compile
        scene_spec = scene_params
        scene_ir = Scene::Compiler.new.compile_scene(scene_spec)
        render json: scene_payload(scene_spec, scene_ir, { "compile_ms" => scene_ir.dig("stats", "compile_ms") }, include_map: include_map?)
      rescue JSON::ParserError => error
        render_error("$", "invalid JSON: #{error.message}", :bad_request)
      rescue Scene::ValidationError => error
        render json: { error: "invalid_scene_spec", errors: error.errors }, status: :unprocessable_entity
      end

      def export
        scene_ir = Scene::Compiler.new.compile_scene(scene_params)
        xml = Roblox::Exporter.new.export(scene_ir)
        filename = "#{scene_ir.fetch("name").parameterize.presence || "roblox-scene"}.rbxlx"
        send_data xml, filename: filename, type: "application/xml", disposition: "attachment"
      rescue JSON::ParserError => error
        render_error("$", "invalid JSON: #{error.message}", :bad_request)
      rescue Scene::ValidationError => error
        render json: { error: "invalid_scene_spec", errors: error.errors }, status: :unprocessable_entity
      end

      private

      def scene_payload(scene_spec, scene_ir, metrics, include_map:)
        return { scene_spec: scene_spec, scene_ir: scene_ir, metrics: metrics.merge("map_ready" => false) } unless include_map

        started_at = monotonic_time
        roblox_file = Roblox::MapArtifact.build(scene_ir)
        complete_metrics = metrics.merge(
          "export_ms" => ((monotonic_time - started_at) * 1000).round(2),
          "rbxlx_bytes" => roblox_file.fetch("byte_size"),
          "map_ready" => true
        )
        { scene_spec: scene_spec, scene_ir: scene_ir, roblox_file: roblox_file, metrics: complete_metrics }
      end

      def include_map?
        params[:include_map].to_s == "true"
      end

      def scene_params
        raw = params[:scene_spec]
        raw = JSON.parse(raw) if raw.is_a?(String)
        raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
        raise JSON::ParserError, "scene_spec is required" unless raw.is_a?(Hash)

        raw
      end

      def render_error(path, message, status)
        render json: { error: "invalid_request", errors: [{ path: path, message: message }] }, status: status
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
