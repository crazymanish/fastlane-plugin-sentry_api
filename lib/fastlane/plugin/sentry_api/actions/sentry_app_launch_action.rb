require 'fastlane/action'
require_relative '../helper/sentry_api_helper'

module Fastlane
  module Actions
    module SharedValues
      SENTRY_APP_LAUNCH_DATA = :SENTRY_APP_LAUNCH_DATA
      SENTRY_APP_LAUNCH_STATUS_CODE = :SENTRY_APP_LAUNCH_STATUS_CODE
      SENTRY_APP_LAUNCH_JSON = :SENTRY_APP_LAUNCH_JSON
    end

    # Query app launch (cold start & warm start) percentiles from the Sentry Events/Discover API.
    # Returns p50, p75, p95 metrics for cold start and warm start durations.
    class SentryAppLaunchAction < Action
      class << self
        def run(params)
          auth_token = params[:auth_token]
          org_slug = params[:org_slug]
          project_id = params[:project_id]

          result = {}

          # Fetch cold start metrics
          cold_params = build_query_params(params, project_id, :cold)
          UI.message("Fetching cold start metrics from Sentry (#{cold_params[:statsPeriod] || 'custom range'})...")

          cold_response = Helper::SentryApiHelper.get_events(
            auth_token: auth_token,
            org_slug: org_slug,
            params: cold_params
          )

          unless cold_response[:status].between?(200, 299)
            UI.user_error!("Sentry Events API error #{cold_response[:status]}: #{cold_response[:body]}")
            return nil
          end

          result[:cold_start] = parse_response(cold_response[:json], :cold)

          # Fetch warm start metrics
          warm_params = build_query_params(params, project_id, :warm)
          UI.message("Fetching warm start metrics from Sentry...")

          warm_response = Helper::SentryApiHelper.get_events(
            auth_token: auth_token,
            org_slug: org_slug,
            params: warm_params
          )

          unless warm_response[:status].between?(200, 299)
            UI.user_error!("Sentry Events API error #{warm_response[:status]}: #{warm_response[:body]}")
            return nil
          end

          result[:warm_start] = parse_response(warm_response[:json], :warm)

          Actions.lane_context[SharedValues::SENTRY_APP_LAUNCH_STATUS_CODE] = cold_response[:status]
          Actions.lane_context[SharedValues::SENTRY_APP_LAUNCH_JSON] = {
            cold: cold_response[:json],
            warm: warm_response[:json]
          }
          Actions.lane_context[SharedValues::SENTRY_APP_LAUNCH_DATA] = result

          log_result(result)

          result
        end

        #####################################################
        # @!group Documentation
        #####################################################

        def description
          "Query app launch (cold start & warm start) latency percentiles from Sentry"
        end

        def details
          [
            "Queries the Sentry Events/Discover API for app launch latency metrics.",
            "Returns p50, p75, and p95 percentiles for both cold start and warm start durations.",
            "",
            "Cold start: Full app initialization from a terminated state.",
            "Warm start: App resume from a backgrounded/cached state.",
            "",
            "Uses Sentry's `measurements.app_start_cold` and `measurements.app_start_warm` fields.",
            "Supports filtering by release, environment, and time range.",
            "",
            "API Documentation: https://docs.sentry.io/api/discover/"
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
            FastlaneCore::ConfigItem.new(key: :org_slug,
                                         env_name: "SENTRY_ORG_SLUG",
                                         description: "Sentry organization slug",
                                         optional: false,
                                         type: String,
                                         verify_block: proc do |value|
                                                         UI.user_error!("No Sentry org slug given, pass using `org_slug: 'my-org'`") if value.to_s.empty?
                                                       end),
            FastlaneCore::ConfigItem.new(key: :project_id,
                                         env_name: "SENTRY_PROJECT_ID",
                                         description: "Sentry numeric project ID",
                                         optional: false,
                                         type: String,
                                         verify_block: proc do |value|
                                                         UI.user_error!("No Sentry project ID given, pass using `project_id: '12345'`") if value.to_s.empty?
                                                       end),
            FastlaneCore::ConfigItem.new(key: :environment,
                                         env_name: "SENTRY_ENVIRONMENT",
                                         description: "Environment filter (e.g. 'production')",
                                         optional: true,
                                         default_value: "production",
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :stats_period,
                                         description: "Rolling time window (e.g. '7d', '14d', '30d')",
                                         optional: true,
                                         default_value: "7d",
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :start_date,
                                         description: "Start date in ISO 8601 format. Use with end_date instead of stats_period",
                                         optional: true,
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :end_date,
                                         description: "End date in ISO 8601 format. Use with start_date instead of stats_period",
                                         optional: true,
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :release,
                                         description: "Filter by specific release version",
                                         optional: true,
                                         type: String)
          ]
        end

        def output
          [
            ['SENTRY_APP_LAUNCH_DATA', 'Hash with :cold_start and :warm_start, each containing :p50, :p75, :p95, :count'],
            ['SENTRY_APP_LAUNCH_STATUS_CODE', 'HTTP status code from the Sentry API'],
            ['SENTRY_APP_LAUNCH_JSON', 'Raw JSON responses from the Sentry API (cold and warm)']
          ]
        end

        def return_value
          "A hash with :cold_start and :warm_start keys, each containing :p50, :p75, :p95 (in ms), and :count."
        end

        def authors
          ["crazymanish"]
        end

        def example_code
          [
            '# Fetch app launch metrics for the last 7 days
            result = sentry_app_launch(stats_period: "7d")
            cold = result[:cold_start]
            warm = result[:warm_start]
            UI.message("Cold start: p50=#{cold[:p50]}ms p95=#{cold[:p95]}ms")
            UI.message("Warm start: p50=#{warm[:p50]}ms p95=#{warm[:p95]}ms")',

            '# Filter by release
            sentry_app_launch(release: "v25.10.0", stats_period: "14d")',

            '# Custom date range
            sentry_app_launch(start_date: "2026-02-24T00:00:00Z", end_date: "2026-03-03T00:00:00Z")'
          ]
        end

        def category
          :misc
        end

        def is_supported?(platform)
          true
        end

        private

        def build_query_params(params, project_id, start_type)
          measurement = start_type == :cold ? 'app_start_cold' : 'app_start_warm'

          fields = [
            "p50(measurements.#{measurement})",
            "p75(measurements.#{measurement})",
            "p95(measurements.#{measurement})",
            'count()'
          ]

          query_parts = ['event.type:transaction']
          query_parts << "has:measurements.#{measurement}"
          query_parts << "release:#{params[:release]}" if params[:release]

          query_params = {
            dataset: 'metrics',
            field: fields,
            project: project_id.to_s,
            query: query_parts.join(' '),
            per_page: '1'
          }

          if params[:start_date] && params[:end_date]
            query_params[:start] = params[:start_date]
            query_params[:end] = params[:end_date]
          else
            query_params[:statsPeriod] = params[:stats_period] || '7d'
          end

          query_params[:environment] = params[:environment] if params[:environment]

          query_params
        end

        def parse_response(json, start_type)
          measurement = start_type == :cold ? 'app_start_cold' : 'app_start_warm'
          row = json&.dig('data', 0) || {}

          {
            p50: round_ms(row["p50(measurements.#{measurement})"]),
            p75: round_ms(row["p75(measurements.#{measurement})"]),
            p95: round_ms(row["p95(measurements.#{measurement})"]),
            count: row['count()']
          }
        end

        def round_ms(value)
          return nil if value.nil?

          value.round(1)
        end

        def log_result(result)
          cold = result[:cold_start]
          warm = result[:warm_start]

          if cold[:p50]
            UI.success("Cold start: p50=#{cold[:p50]}ms p75=#{cold[:p75]}ms p95=#{cold[:p95]}ms (#{cold[:count]} launches)")
          else
            UI.message("Cold start: no data available")
          end

          if warm[:p50]
            UI.success("Warm start: p50=#{warm[:p50]}ms p75=#{warm[:p75]}ms p95=#{warm[:p95]}ms (#{warm[:count]} launches)")
          else
            UI.message("Warm start: no data available")
          end
        end
      end
    end
  end
end
