module Api
  module V1
    class ScenesController < ApplicationController
      MAX_UPLOAD_BYTES = 10 * 1024 * 1024
      ALLOWED_TYPES = %w[image/jpeg image/png image/webp].freeze

      def status
        render json: {
          ok: true,
          vision_configured: ENV["OPENAI_API_KEY"].present?,
          vision_model: ENV.fetch("VISION_MODEL", Vision::SceneAnalyzer::DEFAULT_MODEL),
          component_version: Scene::Compiler::COMPONENT_VERSION
        }
      end

      def schema
        render json: JSON.parse(Rails.root.join("config/schema/scene_spec.schema.json").read)
      end

      def analyze
        started_at = monotonic_time
        upload = params[:photo]
        return render_error("$.photo", "is required", :unprocessable_entity) unless upload.respond_to?(:read)
        return render_error("$.photo", "must be JPEG, PNG, or WebP", :unsupported_media_type) unless ALLOWED_TYPES.include?(upload.content_type)
        return render_error("$.photo", "must be 10 MB or smaller", :payload_too_large) if upload.size > MAX_UPLOAD_BYTES

        analysis = Vision::SceneAnalyzer.new.analyze(
          bytes: upload.read,
          mime_type: upload.content_type,
          filename: upload.original_filename,
          hint: params[:hint]
        )
        scene_ir = Scene::Compiler.new.compile_scene(analysis.fetch(:scene_spec))
        metrics = analysis.fetch(:metrics).merge(
          "compile_ms" => scene_ir.dig("stats", "compile_ms"),
          "total_ms" => ((monotonic_time - started_at) * 1000).round(2)
        )
        render json: { scene_spec: analysis.fetch(:scene_spec), scene_ir: scene_ir, metrics: metrics }
      rescue Vision::SceneAnalyzer::ConfigurationError => error
        render json: { error: "vision_not_configured", message: error.message }, status: :service_unavailable
      rescue Vision::SceneAnalyzer::ApiError => error
        render json: { error: "vision_api_error", message: error.message }, status: :bad_gateway
      rescue Scene::ValidationError => error
        render json: { error: "invalid_scene_spec", errors: error.errors }, status: :unprocessable_entity
      end

      def compile
        scene_spec = scene_params
        scene_ir = Scene::Compiler.new.compile_scene(scene_spec)
        render json: { scene_spec: scene_spec, scene_ir: scene_ir, metrics: { "compile_ms" => scene_ir.dig("stats", "compile_ms") } }
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
