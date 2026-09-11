module Api
  module V1
    module Auth
      class OAuthController < ApplicationController
        before_action :protect_api!, only: :start

        def start
          provider = OAuth::Provider.fetch(params[:provider])
          state = SecureRandom.urlsafe_base64(32)
          cookies.encrypted[state_cookie(provider.name)] = cookie_options.merge(
            value: { nonce: state, created_at: Time.current.to_i },
            expires: 10.minutes.from_now
          )
          render json: { authorization_url: provider.authorization_url(state: state) }
        rescue OAuth::Provider::NotConfigured, OAuth::Provider::Unsupported => error
          render json: { error: error.message }, status: :unprocessable_entity
        end

        def callback
          provider = OAuth::Provider.fetch(params[:provider])
          stored = cookies.encrypted[state_cookie(provider.name)]
          cookies.delete(state_cookie(provider.name), cookie_delete_options)
          unless valid_state?(stored, params[:state])
            return redirect_with_error("oauth_state_invalid")
          end

          profile = provider.profile(code: params[:code])
          user = OAuth::IdentityResolver.call(provider.name, profile)
          sign_in(user)
          redirect_to "#{app_url}/?oauth=success", allow_other_host: true
        rescue OAuth::Provider::Error, ActiveRecord::RecordInvalid => error
          Rails.logger.warn("OAuth callback failed: #{error.class}: #{error.message}")
          redirect_with_error("oauth_failed")
        end

        private

        def state_cookie(provider)
          "scene_foundry_oauth_#{provider}".to_sym
        end

        def valid_state?(stored, supplied)
          return false if stored.blank? || supplied.blank?
          return false if stored["created_at"].to_i < 10.minutes.ago.to_i

          expected = stored["nonce"].to_s
          expected.bytesize == supplied.bytesize && ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
        end

        def redirect_with_error(code)
          redirect_to "#{app_url}/?oauth_error=#{code}", allow_other_host: true
        end

        def app_url
          ENV.fetch("APP_URL", "http://127.0.0.1:5173").delete_suffix("/")
        end
      end
    end
  end
end
