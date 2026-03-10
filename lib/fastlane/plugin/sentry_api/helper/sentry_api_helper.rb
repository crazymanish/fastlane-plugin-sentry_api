require 'fastlane_core/ui/ui'
require 'net/http'
require 'json'
require 'uri'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?(:UI)

  module Helper
    class SentryApiHelper
      BASE_URL = "https://sentry.io/api/0"

      class << self
        # Make a GET request to the Sentry REST API.
        #
        # @param auth_token [String] Sentry auth token (Bearer)
        # @param path [String] API endpoint path (e.g. "/organizations/my-org/sessions/")
        # @param params [Hash] Query parameters. Array values produce repeated keys (field=a&field=b).
        # @param base_url [String] Sentry API base URL
        # @return [Hash] { status: Integer, body: String, json: Object|nil }
        def api_request(auth_token:, path:, params: {}, base_url: BASE_URL)
          url = "#{base_url}#{path}"
          uri = URI(url)
          uri.query = build_query_string(params) unless params.nil? || params.empty?

          UI.verbose("Sentry API GET: #{uri}")

          req = Net::HTTP::Get.new(uri)
          req['Authorization'] = "Bearer #{auth_token}"
          req['Content-Type'] = 'application/json'

          response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.open_timeout = 30
            http.read_timeout = 60
            http.request(req)
          end

          status_code = response.code.to_i
          body = response.body.to_s
          json = parse_json(body)

          { status: status_code, body: body, json: json }
        end

        # GET /api/0/organizations/{org}/sessions/
        # Used for crash-free rates, session counts, user counts.
        def get_sessions(auth_token:, org_slug:, params: {})
          api_request(
            auth_token: auth_token,
            path: "/organizations/#{org_slug}/sessions/",
            params: params
          )
        end

        # GET /api/0/organizations/{org}/events/
        # Used for Discover queries (TTID percentiles, performance metrics).
        def get_events(auth_token:, org_slug:, params: {})
          api_request(
            auth_token: auth_token,
            path: "/organizations/#{org_slug}/events/",
            params: params
          )
        end

        # GET /api/0/projects/{org}/{project}/issues/
        # Used for listing project issues filtered by release, query, etc.
        def get_issues(auth_token:, org_slug:, project_slug:, params: {})
          api_request(
            auth_token: auth_token,
            path: "/projects/#{org_slug}/#{project_slug}/issues/",
            params: params
          )
        end

        private

        # Build a query string that supports repeated parameter keys via Array values.
        # Example: { field: ['a', 'b'], project: 1 } => "field=a&field=b&project=1"
        def build_query_string(params)
          return nil if params.nil? || params.empty?

          pairs = []
          params.each do |key, value|
            next if value.nil?

            if value.is_a?(Array)
              value.each { |v| pairs << [key.to_s, v.to_s] }
            else
              pairs << [key.to_s, value.to_s]
            end
          end

          URI.encode_www_form(pairs)
        end

        def parse_json(value)
          JSON.parse(value)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
