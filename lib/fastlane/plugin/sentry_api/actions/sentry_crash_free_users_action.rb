require 'fastlane/action'
require_relative '../helper/sentry_api_helper'

module Fastlane
  module Actions
    module SharedValues
      SENTRY_CRASH_FREE_USER_RATE_ONLY = :SENTRY_CRASH_FREE_USER_RATE_ONLY
      SENTRY_TOTAL_USERS_ONLY = :SENTRY_TOTAL_USERS_ONLY
      SENTRY_CRASH_FREE_USERS_STATUS_CODE = :SENTRY_CRASH_FREE_USERS_STATUS_CODE
      SENTRY_CRASH_FREE_USERS_JSON = :SENTRY_CRASH_FREE_USERS_JSON
    end

    # Convenience action focused on user-centric crash-free metrics.
    # Queries the same Sentry Sessions API but returns user-focused results.
    class SentryCrashFreeUsersAction < Action
      class << self
        def run(params)
          auth_token = params[:auth_token]
          org_slug = params[:org_slug]
          project_id = params[:project_id]

          query_params = build_query_params(params, project_id)

          UI.message("Fetching crash-free user metrics from Sentry (#{query_params[:statsPeriod] || 'custom range'})...")

          response = Helper::SentryApiHelper.get_sessions(
            auth_token: auth_token,
            org_slug: org_slug,
            params: query_params
          )

          status_code = response[:status]
          json = response[:json]

          unless status_code.between?(200, 299)
            UI.user_error!("Sentry Sessions API error #{status_code}: #{response[:body]}")
            return nil
          end

          result = parse_response(json)

          Actions.lane_context[SharedValues::SENTRY_CRASH_FREE_USERS_STATUS_CODE] = status_code
          Actions.lane_context[SharedValues::SENTRY_CRASH_FREE_USERS_JSON] = json
          Actions.lane_context[SharedValues::SENTRY_CRASH_FREE_USER_RATE_ONLY] = result[:crash_free_user_rate]
          Actions.lane_context[SharedValues::SENTRY_TOTAL_USERS_ONLY] = result[:total_users]

          UI.success("Crash-free users: #{format_pct(result[:crash_free_user_rate])}")
          UI.success("Total unique users: #{result[:total_users]}")

          result
        end

        #####################################################
        # @!group Documentation
        #####################################################

        def description
          "Query crash-free user rate from the Sentry Sessions API"
        end

        def details
          [
            "Convenience action for fetching user-centric crash-free metrics from Sentry.",
            "Queries the Sessions API for crash_free_rate(user) and count_unique(user).",
            "For full session + user metrics, use sentry_crash_free_sessions instead.",
            "",
            "API Documentation: https://docs.sentry.io/api/releases/retrieve-release-health-session-statistics/"
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
                                         type: String)
          ]
        end

        def output
          [
            ['SENTRY_CRASH_FREE_USER_RATE_ONLY', 'Crash-free user rate as a float (e.g. 0.9991)'],
            ['SENTRY_TOTAL_USERS_ONLY', 'Total unique users in the period'],
            ['SENTRY_CRASH_FREE_USERS_STATUS_CODE', 'HTTP status code from the Sentry API'],
            ['SENTRY_CRASH_FREE_USERS_JSON', 'Raw JSON response from the Sentry API']
          ]
        end

        def return_value
          "A hash with :crash_free_user_rate and :total_users."
        end

        def authors
          ["crazymanish"]
        end

        def example_code
          [
            'sentry_crash_free_users(stats_period: "7d")
            rate = lane_context[SharedValues::SENTRY_CRASH_FREE_USER_RATE_ONLY]
            UI.message("Crash-free users: #{(rate * 100).round(2)}%")'
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
            'crash_free_rate(user)',
            'count_unique(user)'
          ]

          query_params = {
            field: fields,
            project: project_id.to_s,
            includeSeries: '0'
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
          groups_data = json&.dig('groups') || []
          totals = groups_data.dig(0, 'totals') || {}

          {
            crash_free_user_rate: totals['crash_free_rate(user)'],
            total_users: totals['count_unique(user)']
          }
        end

        def format_pct(value)
          return "N/A" if value.nil?

          "#{(value * 100).round(4)}%"
        end
      end
    end
  end
end
