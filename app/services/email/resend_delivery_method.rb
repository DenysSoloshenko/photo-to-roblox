require "digest"
require "json"
require "net/http"

module Email
  class ResendDeliveryMethod
    API_URL = "https://api.resend.com/emails"

    class DeliveryError < StandardError; end

    attr_reader :settings

    def initialize(settings = {})
      @settings = {
        api_key: nil,
        api_url: API_URL,
        open_timeout: 5,
        read_timeout: 15
      }.merge(settings)
    end

    def deliver!(message)
      api_key = settings.fetch(:api_key).to_s
      raise DeliveryError, "RESEND_API_KEY is not configured" if api_key.empty?

      uri = URI(settings.fetch(:api_url))
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request["Idempotency-Key"] = idempotency_key(message)
      request.body = JSON.generate(payload(message))

      response = perform_request(uri, request)
      unless response.code.to_i.between?(200, 299)
        raise DeliveryError, "Resend rejected the email (HTTP #{response.code})"
      end

      JSON.parse(response.body).fetch("id")
    rescue JSON::ParserError, KeyError
      raise DeliveryError, "Resend returned an invalid response"
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
      raise DeliveryError, "Resend delivery failed (#{error.class})"
    end

    private

    def payload(message)
      data = {
        from: message[:from].to_s,
        to: Array(message.to),
        subject: message.subject.to_s
      }

      data[:cc] = Array(message.cc) if message.cc.present?
      data[:bcc] = Array(message.bcc) if message.bcc.present?
      data[:reply_to] = Array(message.reply_to) if message.reply_to.present?

      if message.multipart?
        data[:html] = message.html_part.body.decoded if message.html_part
        data[:text] = message.text_part.body.decoded if message.text_part
      elsif message.mime_type == "text/html"
        data[:html] = message.body.decoded
      else
        data[:text] = message.body.decoded
      end

      data
    end

    def idempotency_key(message)
      source = message.message_id.presence || "#{message.subject}:#{message.to.join(',')}:#{message.date.to_i}"
      "scenefoundry/#{Digest::SHA256.hexdigest(source)}"
    end

    def perform_request(uri, request)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: settings.fetch(:open_timeout),
        read_timeout: settings.fetch(:read_timeout)
      ) { |http| http.request(request) }
    end
  end
end
