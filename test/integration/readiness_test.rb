require "test_helper"

class ReadinessTest < ActionDispatch::IntegrationTest
  test "readiness checks database while liveness only checks boot" do
    get "/ready"
    assert_response :success
    ActiveRecord::Base.connection_pool.stub(:with_connection, ->(*) { raise ActiveRecord::ConnectionNotEstablished }) do
      get "/ready"
      assert_response :service_unavailable
      assert_equal({ "status" => "unavailable" }, response.parsed_body)
      get "/up"
      assert_response :success
    end
  end

  test "anonymous session and authorization do not require a database query" do
    User.stub(:find_by, ->(*) { raise "Unexpected database query" }) do
      get "/api/v1/auth/session"
      assert_response :success
      assert_nil response.parsed_body["user"]
      get "/api/v1/orders"
      assert_response :unauthorized
    end
  end
end
