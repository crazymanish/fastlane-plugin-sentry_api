require 'fastlane/action'
require_relative '../helper/sentry_api_helper'

module Fastlane
  module Actions
    module SharedValues
      SENTRY_TTID_DATA = :SENTRY_TTID_DATA
      SENTRY_TTID_STATUS_CODE = :SENTRY_TTID_STATUS_CODE
      SENTRY_TTID_JSON = :SENTRY_TTID_JSON
    end

    # Query Time to Initial Display (TTID) percentiles per screen from the Sentry Events/Discover API.
    # Returns p50, p75, p95 metrics for each screen transaction, sorted by load count.
    class SentryTtidPercentilesAction < Action
      class << self
        def run(params)
          auth_token = params[:auth_token]
          org_slug = params[:org_slug]
          project_id = params[:project_id]

          query_params = build_query_params(params, project_id)

          UI.message("Fetching TTID percentiles from Sentry (#{query_params[:statsPeriod] || 'custom range'})...")

          response = Helper::SentryApiHelper.get_events(
            auth_token: auth_token,
            org_slug: org_slug,
            params: query_params
          )

          status_code = response[:status]
          json = response[:json]

          unless status_code.between?(200, 299)
            UI.user_error!("Sentry Events API error #{status_code}: #{response[:body]}")
            return nil
          end

          result = parse_response(json)

          Actions.lane_context[SharedValues::SENTRY_TTID_STATUS_CODE] = status_code
          Actions.lane_context[SharedValues::SENTRY_TTID_JSON] = json
          Actions.lane_context[SharedValues::SENTRY_TTID_DATA] = result

          UI.success("Fetched TTID data for #{result.length} screens")
          result.first(5).each do |screen|
            UI.message("  #{screen[:transaction]}: p50=#{screen[:p50]}ms p75=#{screen[:p75]}ms p95=#{screen[:p95]}ms (#{screen[:count]} loads)")
          end

          result
        end

        #####################################################
        # @!group Documentation
        #####################################################

        def description
          "Query TTID (Time to Initial Display) percentiles per screen from Sentry"
        end

        def details
          [
            "Queries the Sentry Events/Discover API for Time to Initial Display (TTID) metrics.",
            "Returns p50, p75, and p95 percentiles per screen transaction, sorted by load count.",
            "Useful for monitoring app launch performance and screen rendering latency.",
            "",
            "Supports filtering by release, environment, and transaction operation type.",
            "Use `stats_period` for rolling windows or `start_date` + `end_date` for specific ranges.",
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
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :transaction_op,
                                         description: "Transaction operation filter (e.g. 'ui.load', 'ui.action')",
                                         optional: true,
                                         default_value: "ui.load",
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :per_page,
                                         description: "Number of screens to return (max 100)",
                                         optional: true,
                                         default_value: 20,
                                         type: Integer),
            FastlaneCore::ConfigItem.new(key: :sort,
                                         description: "Sort order (e.g. '-count()', '-p95(measurements.time_to_initial_display)')",
                                         optional: true,
                                         default_value: "-count()",
                                         type: String)
          ]
        end

        def output
          [
            ['SENTRY_TTID_DATA', 'Array of hashes with :transaction, :p50, :p75, :p95, :count per screen'],
            ['SENTRY_TTID_STATUS_CODE', 'HTTP status code from the Sentry API'],
            ['SENTRY_TTID_JSON', 'Raw JSON response from the Sentry API']
          ]
        end

        def return_value
          "An array of hashes, each with :transaction (screen name), :p50, :p75, :p95 (in ms), and :count (number of loads)."
        end

        def authors
          ["crazymanish"]
        end

        def example_code
          [
            '# Top 10 screens by load count, last 7 days
            screens = sentry_ttid_percentiles(stats_period: "7d", per_page: 10)
            screens.each do |s|
              UI.message("#{s[:transaction]}: p50=#{s[:p50]}ms p95=#{s[:p95]}ms (#{s[:count]} loads)")
            end',

            '# Filter by release
            sentry_ttid_percentiles(release: "v25.10.0", stats_period: "14d")',

            '# Custom date range (for week-over-week comparison)
            sentry_ttid_percentiles(start_date: "2026-02-24T00:00:00Z", end_date: "2026-03-03T00:00:00Z")'
          ]
        end

        def category
          :misc
        end

        def is_supported?(platform)
          true
        end

        private

        def build_query_params(params, project_id)
          fields = [
            'transaction',
            'p50(measurements.time_to_initial_display)',
            'p75(measurements.time_to_initial_display)',
            'p95(measurements.time_to_initial_display)',
            'count()'
          ]

          # Build the query filter
          query_parts = ["event.type:transaction"]
          query_parts << "transaction.op:#{params[:transaction_op]}" if params[:transaction_op]
          query_parts << "release:#{params[:release]}" if params[:release]

          query_params = {
            dataset: 'metrics',
            field: fields,
            project: project_id.to_s,
            query: query_parts.join(' '),
            sort: params[:sort] || '-count()',
            per_page: (params[:per_page] || 20).to_s
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

        def parse_response(json)
          data = json&.dig('data') || []

          data.map do |row|
            {
              transaction: row['transaction'],
              p50: round_ms(row['p50(measurements.time_to_initial_display)']),
              p75: round_ms(row['p75(measurements.time_to_initial_display)']),
              p95: round_ms(row['p95(measurements.time_to_initial_display)']),
              count: row['count()']
            }
          end
        end

        def round_ms(value)
          return nil if value.nil?

          value.round(1)
        end
      end
    end
  end
end
