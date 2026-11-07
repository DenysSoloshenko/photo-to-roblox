module Orders
  class ProductionReadiness
    def self.problems
      problems = []
      problems << "private S3 storage is required" unless Rails.application.config.active_storage.service.to_s == "amazon" && ENV["S3_BUCKET"].present?
      problems << "a durable job queue is required" unless ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
      problems << "email delivery is required" if ActionMailer::Base.delivery_method.in?(%i[test file]) || !ActionMailer::Base.perform_deliveries
      problems << "a live background worker is required" unless SolidQueue::Process.where(kind: "Worker").where("last_heartbeat_at > ?", 2.minutes.ago).exists?
      problems
    end

    def self.verify!(error_class)
      return unless Rails.env.production?
      failures = problems
      raise error_class, "Fulfillment is not ready: #{failures.join('; ')}" if failures.any?
    end
  end
end
