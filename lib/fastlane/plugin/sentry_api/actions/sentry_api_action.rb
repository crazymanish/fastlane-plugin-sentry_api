require 'fastlane/action'
require_relative '../helper/sentry_api_helper'

module Fastlane
  module Actions
    module SharedValues
      SENTRY_API_STATUS_CODE = :SENTRY_API_STATUS_CODE
      SENTRY_API_RESPONSE = :SENTRY_API_RESPONSE
      SENTRY_API_JSON = :SENTRY_API_JSON
    end

    # Generic action for making raw GET requests to any Sentry REST API endpoint.
    # Use the specific actions (sentry_crash_free_sessions, sentry_ttid_percentiles, etc.)
    # for common use cases. This action is a fallback for endpoints not covered by specific actions.
    class SentryApiAction < Action
      class << self
        def run(params)
          response = Helper::SentryApiHelper.api_request(
            auth_token: params[:auth_token],
            path: params[:path],
            params: params[:params] || {},
            base_url: params[:server_url]
          )

          status_code = response[:status]
          json = response[:json]

          unless status_code.between?(200, 299)
            UI.error("Sentry API error #{status_code}: #{response[:body]}")
            UI.user_error!("Sentry API returned #{status_code}")
            return nil
          end

          Actions.lane_context[SharedValues::SENTRY_API_STATUS_CODE] = status_code
          Actions.lane_context[SharedValues::SENTRY_API_RESPONSE] = response[:body]
          Actions.lane_context[SharedValues::SENTRY_API_JSON] = json

          UI.success("Sentry API request successful (#{status_code})")

          { status: status_code, body: response[:body], json: json }
        end

        #####################################################
        # @!group Documentation
        #####################################################

        def description
          "Make a generic GET request to the Sentry REST API"
        end

        def details
          [
            "Makes a generic GET request to the Sentry REST API.",
            "Use this action for any Sentry API endpoint not covered by the specific actions.",
            "API Documentation: https://docs.sentry.io/api/"
          ].join("\n")
        end

        def available_options
          [
            FastlaneCore::ConfigItem.new(key: :auth_token,
                                         env_name: "SENTRY_AUTH_TOKEN",
                                         description: "Sentry API Bearer auth token",
                                         optional: false,
                                         type: String,
                                         sensitive: true,
                                         code_gen_sensitive: true,
                                         verify_block: proc do |value|
                                                         UI.user_error!("No Sentry auth token given, pass using `auth_token: 'token'`") if value.to_s.empty?
                                                       end),
            FastlaneCore::ConfigItem.new(key: :server_url,
                                         env_name: "SENTRY_API_SERVER_URL",
                                         description: "Sentry API base URL",
                                         optional: true,
                                         default_value: "https://sentry.io/api/0",
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :path,
                                         description: "API endpoint path (e.g. '/organizations/my-org/sessions/')",
                                         optional: false,
                                         type: String,
                                         verify_block: proc do |value|
                                                         UI.user_error!("API path cannot be empty") if value.to_s.empty?
                                                       end),
            FastlaneCore::ConfigItem.new(key: :params,
                                         description: "Query parameters hash. Array values produce repeated keys.",
                                         optional: true,
                                         default_value: {},
                                         type: Hash)
          ]
        end

        def output
          [
            ['SENTRY_API_STATUS_CODE', 'The HTTP status code returned from the Sentry API'],
            ['SENTRY_API_RESPONSE', 'The full response body from the Sentry API'],
            ['SENTRY_API_JSON', 'The parsed JSON returned from the Sentry API']
          ]
        end

        def return_value
          "A hash including the HTTP status code (:status), the response body (:body), and the parsed JSON (:json)."
        end

        def authors
          ["crazymanish"]
        end

        def example_code
          [
            'result = sentry_api(
              auth_token: ENV["SENTRY_AUTH_TOKEN"],
              path: "/organizations/my-org/sessions/",
              params: { field: ["crash_free_rate(session)"], statsPeriod: "7d", project: "12345" }
            )
            UI.message("Response: #{result[:json]}")'
          ]
        end

        def category
          :misc
        end

        def is_supported?(platform)
          true
        end
      end
    end
  end
end
