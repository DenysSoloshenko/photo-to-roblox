require "test_helper"

class ProductionReadinessTest < ActiveSupport::TestCase
  test "the ephemeral development configuration is not eligible for production payments" do
    failures = Orders::ProductionReadiness.problems
    assert_includes failures, "private S3 storage is required"
    assert_includes failures, "a durable job queue is required"
    assert_includes failures, "email delivery is required"
    assert_includes failures, "a live background worker is required"
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      assert_raises(Payments::StripeCheckout::NotConfigured) do
        Orders::ProductionReadiness.verify!(Payments::StripeCheckout::NotConfigured)
      end
    end
  end
end
