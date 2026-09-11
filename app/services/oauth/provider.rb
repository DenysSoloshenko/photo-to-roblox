require "net/http"

module OAuth
  class Provider
    class Error < StandardError; end
    class Unsupported < Error; end
    class NotConfigured < Error; end

    SETTINGS = {
      "google" => {
        authorize_url: "https://accounts.google.com/o/oauth2/v2/auth",
        token_url: "https://oauth2.googleapis.com/token",
        profile_url: "https://openidconnect.googleapis.com/v1/userinfo",
        scope: "openid email profile"
      },
      "github" => {
        authorize_url: "https://github.com/login/oauth/authorize",
        token_url: "https://github.com/login/oauth/access_token",
        profile_url: "https://api.github.com/user",
        emails_url: "https://api.github.com/user/emails",
        scope: "user:email"
      },
      "discord" => {
        authorize_url: "https://discord.com/oauth2/authorize",
        token_url: "https://discord.com/api/oauth2/token",
        profile_url: "https://discord.com/api/users/@me",
        scope: "identify email"
      }
    }.freeze

    Profile = Data.define(:uid, :email, :email_verified, :name)

    attr_reader :name

    def self.fetch(name)
      name = name.to_s
      raise Unsupported, "Unsupported OAuth provider" unless SETTINGS.key?(name)

      provider = new(name)
      raise NotConfigured, "#{name.capitalize} login is not configured" unless provider.configured?
      provider
    end

    def self.configured_names
      SETTINGS.keys.select { |name| new(name).configured? }
    end

    def self.statuses
      SETTINGS.keys.map { |name| { name: name, configured: new(name).configured? } }
    end

    def initialize(name)
      @name = name
      @settings = SETTINGS.fetch(name)
    end

    def configured?
      client_id.present? && client_secret.present?
    end

    def authorization_url(state:)
      query = {
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: @settings.fetch(:scope),
        state: state
      }
      query[:access_type] = "online" if name == "google"
      "#{@settings.fetch(:authorize_url)}?#{URI.encode_www_form(query)}"
    end

    def profile(code:)
      raise Error, "Authorization was cancelled" if code.blank?

      token = exchange_code(code)
      profile_data = get_json(@settings.fetch(:profile_url), token)
      build_profile(profile_data, token)
    end

    private

    def client_id
      ENV["#{name.upcase}_CLIENT_ID"]
    end

    def client_secret
      ENV["#{name.upcase}_CLIENT_SECRET"]
    end

    def redirect_uri
      "#{ENV.fetch("API_URL", "http://127.0.0.1:3000").delete_suffix("/")}/api/v1/auth/oauth/#{name}/callback"
    end

    def exchange_code(code)
      uri = URI(@settings.fetch(:token_url))
      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/json"
      request.set_form_data(
        client_id: client_id,
        client_secret: client_secret,
        code: code,
        redirect_uri: redirect_uri,
        grant_type: "authorization_code"
      )
      body = perform_json(uri, request)
      body.fetch("access_token")
    rescue KeyError
      raise Error, "OAuth provider did not return an access token"
    end

    def get_json(url, token)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["Authorization"] = "Bearer #{token}"
      request["User-Agent"] = "SceneFoundry"
      perform_json(uri, request)
    end

    def perform_json(uri, request)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
        http.request(request)
      end
      raise Error, "OAuth provider returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise Error, "OAuth provider returned an invalid response"
    rescue Timeout::Error, SocketError, SystemCallError => error
      raise Error, "OAuth provider is unavailable: #{error.message}"
    end

    def build_profile(data, token)
      case name
      when "google"
        Profile.new(uid: data.fetch("sub"), email: data["email"], email_verified: data["email_verified"] == true, name: data["name"])
      when "discord"
        Profile.new(uid: data.fetch("id"), email: data["email"], email_verified: data["verified"] == true, name: data["global_name"].presence || data["username"])
      when "github"
        email_data = github_email(data, token)
        Profile.new(uid: data.fetch("id").to_s, email: email_data&.fetch("email", nil), email_verified: email_data&.fetch("verified", false) == true, name: data["name"].presence || data["login"])
      end
    rescue KeyError
      raise Error, "OAuth profile is missing an account identifier"
    end

    def github_email(profile_data, token)
      emails = get_json(@settings.fetch(:emails_url), token)
      verified = emails.select { |candidate| candidate["verified"] }
      verified.find { |candidate| candidate["primary"] } ||
        verified.find { |candidate| candidate["email"] == profile_data["email"] } ||
        verified.first
    end
  end
end
