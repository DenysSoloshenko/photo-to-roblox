require "stringio"

module Orders
  class PremiumGenerator
    def initialize(order, analyzer_factory: Vision::SceneAnalyzer, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @order = order
      @analyzer_factory = analyzer_factory
      @clock = clock
    end

    def call
      started_at = clock.call
      photo = order.source_photos.first
      raise ArgumentError, "order has no source photograph" unless photo

      analysis = analyzer_factory.for_quality("astra_max").analyze(
        bytes: photo.download,
        mime_type: photo.content_type,
        filename: photo.filename.to_s,
        hint: generation_hint
      )
      order.with_lock { order.update!(generation_metrics: analysis.fetch(:metrics)) }
      geometry = Scene::GeometryNormalizer.new(analysis.fetch(:scene_spec)).normalize
      budget = Scene::BudgetNormalizer.new(geometry.fetch(:scene_spec)).normalize
      scene_spec = budget.fetch(:scene_spec)
      scene_ir = Scene::Compiler.new.compile_scene(scene_spec)
      xml = Roblox::Exporter.new.export(scene_ir)
      filename = "#{scene_ir.fetch("name").parameterize.presence || "roblox-scene"}.rbxlx"
      metrics = analysis.fetch(:metrics).merge(geometry.fetch(:metrics)).merge(budget.fetch(:metrics)).merge(
        "compile_ms" => scene_ir.dig("stats", "compile_ms"),
        "rbxlx_bytes" => xml.bytesize,
        "total_ms" => ((clock.call - started_at) * 1_000).round(2)
      )

      order.with_lock do
        raise ActiveRecord::RecordInvalid, order unless order.status == "building" && order.payment_status == "paid"

        order.result_file.attach(io: StringIO.new(xml), filename: filename, content_type: "application/xml")
        order.update!(
          preview_scene_ir: scene_ir,
          generation_metrics: metrics,
          generation_finished_at: Time.current,
          generation_error: nil,
          status: "reviewing"
        )
      end
      Rails.logger.info({ event: "premium_generation_completed", order_id: order.public_id, metrics: metrics }.to_json)
      order
    end

    private

    attr_reader :order, :analyzer_factory, :clock

    def generation_hint
      [order.must_preserve, order.instructions].compact_blank.join("\n")
    end
  end
end
