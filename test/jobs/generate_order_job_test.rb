require "test_helper"

class GenerateOrderJobTest < ActiveJob::TestCase
  FakeAnalyzer = Struct.new(:scene_spec) do
    def analyze(**)
      { scene_spec: scene_spec, metrics: { "vision_model" => "gpt-6-astra", "quality_mode" => "astra_max", "api_cost_usd" => 2.75 } }
    end
  end

  setup do
    @original_environment = %w[
      OPENAI_API_KEY ASTRA_QUALITY_ENABLED ASTRA_ORDER_AUTOMATION_ENABLED
      ASTRA_ORDER_MAX_CONCURRENT ASTRA_ORDER_DAILY_SPEND_LIMIT_USD ASTRA_ORDER_COST_RESERVATION_USD
    ].to_h { |name| [name, ENV[name]] }
    ENV["OPENAI_API_KEY"] = "test-key"
    ENV["ASTRA_QUALITY_ENABLED"] = "true"
    ENV["ASTRA_ORDER_AUTOMATION_ENABLED"] = "true"
    ENV["ASTRA_ORDER_MAX_CONCURRENT"] = "1"
    ENV["ASTRA_ORDER_DAILY_SPEND_LIMIT_USD"] = "30"
    ENV["ASTRA_ORDER_COST_RESERVATION_USD"] = "3"
  end

  teardown do
    @original_environment.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end

  test "builds a private premium result only for a paid building order" do
    order = paid_building_order("Premium park")
    analyzer = FakeAnalyzer.new(JSON.parse(Rails.root.join("examples/park.json").read))

    Vision::SceneAnalyzer.stub(:for_quality, ->(mode) { assert_equal "astra_max", mode; analyzer }) do
      GenerateOrderJob.perform_now(order.id)
    end

    order.reload
    assert_equal "reviewing", order.status
    assert_equal 1, order.generation_attempts
    assert order.generation_started_at.present?
    assert order.generation_finished_at.present?
    assert_equal 2.75, order.generation_metrics.fetch("api_cost_usd")
    assert_equal "gpt-6-astra", order.generation_metrics.fetch("vision_model")
    assert order.preview_scene_ir.present?
    assert order.result_file.attached?
    refute order.ready_for_download?
  end

  test "does not call the analyzer for an unpaid order" do
    user = user_for("unpaid")
    order = user.orders.create!(title: "Unpaid", rights_confirmed_at: Time.current)
    called = false

    Vision::SceneAnalyzer.stub(:for_quality, ->(*) { called = true }) do
      GenerateOrderJob.perform_now(order.id)
    end

    refute called
    assert_equal "payment_pending", order.reload.status
    assert_equal 0, order.generation_attempts
  end

  test "records a private failure without spending when automation is disabled" do
    order = paid_building_order("Disabled automation")
    ENV["ASTRA_ORDER_AUTOMATION_ENABLED"] = "false"
    called = false

    Vision::SceneAnalyzer.stub(:for_quality, ->(*) { called = true }) do
      GenerateOrderJob.perform_now(order.id)
    end

    refute called
    assert_equal "failed", order.reload.status
    assert_match(/automation is disabled/, order.generation_error)
    assert_equal 0, order.generation_attempts
  end

  test "enforces the default cross-order concurrency limit" do
    active = paid_building_order("Already active")
    active.update!(generation_started_at: Time.current)
    waiting = paid_building_order("Waiting")

    GenerateOrderJob.perform_now(waiting.id)

    assert_equal "failed", waiting.reload.status
    assert_match(/concurrency limit/, waiting.generation_error)
    assert_equal 0, waiting.generation_attempts
  end

  test "reserves budget for active generations before starting another" do
    ENV["ASTRA_ORDER_MAX_CONCURRENT"] = "2"
    ENV["ASTRA_ORDER_DAILY_SPEND_LIMIT_USD"] = "5"
    active = paid_building_order("Reserved spend")
    active.update!(generation_started_at: Time.current)
    waiting = paid_building_order("Over projected budget")

    GenerateOrderJob.perform_now(waiting.id)

    assert_equal "failed", waiting.reload.status
    assert_match(/daily spend limit/, waiting.generation_error)
    assert_equal 0, waiting.generation_attempts
  end

  private

  def paid_building_order(title)
    order = user_for(title.parameterize).orders.create!(title: title, rights_confirmed_at: Time.current)
    order.source_photos.attach(io: StringIO.new("photo"), filename: "source.jpg", content_type: "image/jpeg")
    order.update!(status: "submitted", payment_status: "authorized", authorized_at: Time.current, authorization_expires_at: 5.days.from_now)
    order.update!(status: "accepted", payment_status: "capture_pending", capture_requested_at: Time.current)
    order.update!(status: "building", payment_status: "paid", paid_at: Time.current, captured_at: Time.current)
    order
  end

  def user_for(suffix)
    User.create!(email: "#{suffix}@example.com", display_name: suffix.titleize, password: "secure-password")
  end
end
