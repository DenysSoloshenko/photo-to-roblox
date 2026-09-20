require "test_helper"

class EmailResendDeliveryMethodTest < ActiveSupport::TestCase
  test "sends multipart mail through the Resend API without exposing the key in the payload" do
    delivery = Email::ResendDeliveryMethod.new(api_key: "re_secret")
    response = Struct.new(:code, :body).new("200", JSON.generate(id: "email_123"))
    captured_request = nil

    delivery.stub(:perform_request, ->(_uri, request) { captured_request = request; response }) do
      result = delivery.deliver!(sample_message)
      assert_equal "email_123", result
    end

    payload = JSON.parse(captured_request.body)
    assert_equal "SceneFoundry <orders@example.com>", payload.fetch("from")
    assert_equal ["customer@example.com"], payload.fetch("to")
    assert_equal "Reset your SceneFoundry password", payload.fetch("subject")
    assert_includes payload.fetch("html"), "Reset link"
    assert_includes payload.fetch("text"), "Reset link"
    assert_equal "Bearer re_secret", captured_request["Authorization"]
    refute_includes captured_request.body, "re_secret"
    assert_match(/\Ascenefoundry\/[0-9a-f]{64}\z/, captured_request["Idempotency-Key"])
  end

  test "requires an API key" do
    error = assert_raises(Email::ResendDeliveryMethod::DeliveryError) do
      Email::ResendDeliveryMethod.new.deliver!(sample_message)
    end

    assert_equal "RESEND_API_KEY is not configured", error.message
  end

  test "does not copy the provider response into delivery errors" do
    delivery = Email::ResendDeliveryMethod.new(api_key: "re_secret")
    response = Struct.new(:code, :body).new("422", '{"message":"customer@example.com is invalid"}')

    error = delivery.stub(:perform_request, response) do
      assert_raises(Email::ResendDeliveryMethod::DeliveryError) { delivery.deliver!(sample_message) }
    end

    assert_equal "Resend rejected the email (HTTP 422)", error.message
    refute_includes error.message, "customer@example.com"
  end

  private

  def sample_message
    Mail.new do
      from "SceneFoundry <orders@example.com>"
      to "customer@example.com"
      subject "Reset your SceneFoundry password"
      message_id "password-reset-123@example.com"

      text_part do
        body "Reset link: https://example.com/?reset_token=secret"
      end

      html_part do
        content_type "text/html; charset=UTF-8"
        body "<p>Reset link</p>"
      end
    end
  end
end
