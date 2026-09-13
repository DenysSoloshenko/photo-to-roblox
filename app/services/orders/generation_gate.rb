module Orders
  class GenerationGate
    class Disabled < StandardError; end
    class LimitExceeded < StandardError; end

    def initialize(order)
      @order = order
    end

    def reserve!
      Order.transaction do
        acquire_db_gate!
        order.lock!
        return false unless order.status == "building" && order.payment_status == "paid"
        return false if order.generation_started_at.present?

        verify_configuration!
        verify_limits!
        order.update!(
          generation_started_at: Time.current,
          generation_finished_at: nil,
          generation_error: nil,
          generation_attempts: order.generation_attempts + 1
        )
      end
      true
    end

    private

    attr_reader :order

    def verify_configuration!
      raise Disabled, "premium generation automation is disabled" unless enabled?("ASTRA_ORDER_AUTOMATION_ENABLED")
      raise Disabled, "Astra quality mode is disabled" unless enabled?("ASTRA_QUALITY_ENABLED")
      raise Disabled, "OPENAI_API_KEY is not configured" if ENV["OPENAI_API_KEY"].blank?
    end

    def verify_limits!
      concurrent_limit = positive_integer("ASTRA_ORDER_MAX_CONCURRENT", 1)
      active_count = Order.where(status: "building", payment_status: "paid")
        .where.not(generation_started_at: nil)
        .where(generation_finished_at: nil)
        .where.not(id: order.id)
        .count
      raise LimitExceeded, "premium generation concurrency limit reached" if active_count >= concurrent_limit

      daily_limit = positive_decimal("ASTRA_ORDER_DAILY_SPEND_LIMIT_USD", 30)
      reserved_cost = positive_decimal("ASTRA_ORDER_COST_RESERVATION_USD", 3)
      spent_today = Order.where(generation_finished_at: Time.current.beginning_of_day..Time.current.end_of_day)
        .sum("COALESCE((generation_metrics->>'api_cost_usd')::numeric, 0)")
        .to_d
      projected_spend = spent_today + ((active_count + 1) * reserved_cost)
      raise LimitExceeded, "premium generation daily spend limit reached" if projected_spend > daily_limit
    end

    def acquire_db_gate!
      Order.connection.execute("SELECT pg_advisory_xact_lock(709190019)")
    end

    def enabled?(name)
      ActiveModel::Type::Boolean.new.cast(ENV.fetch(name, "false"))
    end

    def positive_integer(name, default)
      value = Integer(ENV.fetch(name, default.to_s), exception: false)
      value&.positive? ? value : default
    end

    def positive_decimal(name, default)
      value = BigDecimal(ENV.fetch(name, default.to_s), exception: false)
      value&.positive? ? value : default.to_d
    end
  end
end
