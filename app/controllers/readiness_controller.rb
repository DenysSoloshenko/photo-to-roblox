class ReadinessController < ApplicationController
  def show
    # Exercise the tables needed by sign-in and ordering; /up only checks boot.
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      %w[users orders email_deliveries solid_queue_jobs].each do |table|
        connection.execute("SELECT 1 FROM #{connection.quote_table_name(table)} LIMIT 1")
      end
    end
    render json: { status: "ready" }
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.error({ event: "readiness_failed", error_class: error.class.name }.to_json)
    render json: { status: "unavailable" }, status: :service_unavailable
  end
end
