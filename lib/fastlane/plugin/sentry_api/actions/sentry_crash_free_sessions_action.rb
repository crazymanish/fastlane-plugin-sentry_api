require 'fastlane/action'
require_relative '../helper/sentry_api_helper'

module Fastlane
  module Actions
    module SharedValues
      SENTRY_CRASH_FREE_SESSION_RATE = :SENTRY_CRASH_FREE_SESSION_RATE
      SENTRY_CRASH_FREE_USER_RATE = :SENTRY_CRASH_FREE_USER_RATE
      SENTRY_TOTAL_SESSIONS = :SENTRY_TOTAL_SESSIONS
      SENTRY_TOTAL_USERS = :SENTRY_TOTAL_USERS
      SENTRY_SESSION_GROUPS = :SENTRY_SESSION_GROUPS
      SENTRY_CRASH_FREE_SESSIONS_STATUS_CODE = :SENTRY_CRASH_FREE_SESSIONS_STATUS_CODE
      SENTRY_CRASH_FREE_SESSIONS_JSON = :SENTRY_CRASH_FREE_SESSIONS_JSON
    end

    # Query crash-free session and user rates from the Sentry Sessions API.
    # Supports aggregate metrics (for week-over-week) and grouped-by-release (for release-over-release).
    class SentryCrashFreeSessionsAction < Action
      class << self
        def run(params)
          auth_token = params[:auth_token]
          org_slug = params[:org_slug]
          project_id = params[:project_id]

          query_params = build_query_params(params, project_id)

          UI.message("Fetching crash-free session metrics from Sentry (#{query_params[:statsPeriod] || 'custom range'})...")

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

          result = parse_response(json, params[:group_by])

          # Store in lane context
          Actions.lane_context[SharedValues::SENTRY_CRASH_FREE_SESSIONS_STATUS_CODE] = status_code
          Actions.lane_context[SharedValues::SENTRY_CRASH_FREE_SESSIONS_JSON] = json
          Actions.lane_context[SharedValues::SENTRY_CRASH_FREE_SESSION_RATE] = result[:crash_free_session_rate]
          Actions.lane_context[SharedValues::SENTRY_CRASH_FREE_USER_RATE] = result[:crash_free_user_rate]
          Actions.lane_context[SharedValues::SENTRY_TOTAL_SESSIONS] = result[:total_sessions]
          Actions.lane_context[SharedValues::SENTRY_TOTAL_USERS] = result[:total_users]
          Actions.lane_context[SharedValues::SENTRY_SESSION_GROUPS] = result[:groups]

          # Log results
          if result[:groups] && !result[:groups].empty?
            UI.success("Fetched #{result[:groups].length} session groups")
            result[:groups].each do |group|
              label = group[:by].values.first || "aggregate"
              UI.message("  #{label}: sessions=#{format_pct(group[:crash_free_session_rate])} users=#{format_pct(group[:crash_free_user_rate])}")
            end
          else
            UI.success("Crash-free sessions: #{format_pct(result[:crash_free_session_rate])}")
            UI.success("Crash-free users: #{format_pct(result[:crash_free_user_rate])}")
            UI.success("Total sessions: #{result[:total_sessions]}, Total users: #{result[:total_users]}")
          end

          result
        end

        #####################################################
        # @!group Documentation
        #####################################################

        def description
          "Query crash-free session and user rates from the Sentry Sessions API"
        end

        def details
          [
            "Queries the Sentry Sessions API for crash-free session rates, crash-free user rates,",
            "total sessions, and total users. Supports aggregate metrics for a time period",
            "(useful for week-over-week comparison) and grouped-by-release metrics",
            "(useful for release-over-release comparison).",
            "",
            "Use `stats_period` for rolling windows (e.g. '7d', '14d', '30d'),",
            "or `start_date` + `end_date` for a specific date range.",
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
                                  description: "Rolling time window (e.g. '7d', '14d', '30d'). Mutually exclusive with start_date/end_date",
                                     optional: true,
                                default_value: "7d",
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :start_date,
                                  description: "Start date in ISO 8601 format (e.g. '2026-03-01T00:00:00Z'). Use with end_date instead of stats_period",
                                     optional: true,
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :end_date,
                                  description: "End date in ISO 8601 format (e.g. '2026-03-08T00:00:00Z'). Use with start_date instead of stats_period",
                                     optional: true,
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :group_by,
                                  description: "Group results by dimension: 'release', 'environment', or nil for aggregate",
                                     optional: true,
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :per_page,
                                  description: "Number of groups to return when group_by is set (max 100)",
                                     optional: true,
                                default_value: 10,
                                         type: Integer),
            FastlaneCore::ConfigItem.new(key: :order_by,
                                  description: "Sort order for grouped results (e.g. '-sum(session)', '-crash_free_rate(session)')",
                                     optional: true,
                                default_value: "-sum(session)",
                                         type: String)
          ]
        end

        def output
          [
            ['SENTRY_CRASH_FREE_SESSION_RATE', 'Crash-free session rate as a float (e.g. 0.9974)'],
            ['SENTRY_CRASH_FREE_USER_RATE', 'Crash-free user rate as a float (e.g. 0.9981)'],
            ['SENTRY_TOTAL_SESSIONS', 'Total number of sessions in the period'],
            ['SENTRY_TOTAL_USERS', 'Total number of unique users in the period'],
            ['SENTRY_SESSION_GROUPS', 'Array of group hashes when group_by is set'],
            ['SENTRY_CRASH_FREE_SESSIONS_STATUS_CODE', 'HTTP status code from the Sentry API'],
            ['SENTRY_CRASH_FREE_SESSIONS_JSON', 'Raw JSON response from the Sentry API']
          ]
        end

        def return_value
          "A hash with :crash_free_session_rate, :crash_free_user_rate, :total_sessions, :total_users, and :groups (when group_by is set)."
        end

        def authors
          ["crazymanish"]
        end

        def example_code
          [
            '# Aggregate crash-free rate for last 7 days
            sentry_crash_free_sessions(stats_period: "7d")
            rate = lane_context[SharedValues::SENTRY_CRASH_FREE_SESSION_RATE]
            UI.message("Crash-free sessions: #{(rate * 100).round(2)}%")',

            '# Grouped by release (release-over-release comparison)
            result = sentry_crash_free_sessions(stats_period: "30d", group_by: "release", per_page: 5)
            result[:groups].each do |g|
              puts "#{g[:by]["release"]}: #{(g[:crash_free_session_rate] * 100).round(2)}%"
            end',

            '# Custom date range (previous week for week-over-week)
            sentry_crash_free_sessions(start_date: "2026-02-24T00:00:00Z", end_date: "2026-03-03T00:00:00Z")'
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
            'crash_free_rate(session)',
            'crash_free_rate(user)',
            'sum(session)',
            'count_unique(user)'
          ]

          query_params = {
            field: fields,
            project: project_id.to_s,
            includeSeries: '0'
          }

          # Time range: stats_period OR start/end
          if params[:start_date] && params[:end_date]
            query_params[:start] = params[:start_date]
            query_params[:end] = params[:end_date]
          else
            query_params[:statsPeriod] = params[:stats_period] || '7d'
          end

          query_params[:environment] = params[:environment] if params[:environment]

          # Grouping
          if params[:group_by]
            query_params[:groupBy] = params[:group_by]
            query_params[:per_page] = params[:per_page].to_s if params[:per_page]
            query_params[:orderBy] = params[:order_by] if params[:order_by]
          end

          query_params
        end

        def parse_response(json, group_by)
          groups_data = json&.dig('groups') || []

          if group_by && !group_by.empty?
            # Grouped response: return array of group results
            groups = groups_data.map do |group|
              totals = group['totals'] || {}
              {
                by: group['by'] || {},
                crash_free_session_rate: totals['crash_free_rate(session)'],
                crash_free_user_rate: totals['crash_free_rate(user)'],
                total_sessions: totals['sum(session)'],
                total_users: totals['count_unique(user)']
              }
            end

            {
              crash_free_session_rate: nil,
              crash_free_user_rate: nil,
              total_sessions: nil,
              total_users: nil,
              groups: groups
            }
          else
            # Aggregate response: single group
            totals = groups_data.dig(0, 'totals') || {}

            {
              crash_free_session_rate: totals['crash_free_rate(session)'],
              crash_free_user_rate: totals['crash_free_rate(user)'],
              total_sessions: totals['sum(session)'],
              total_users: totals['count_unique(user)'],
              groups: nil
            }
          end
        end

        def format_pct(value)
          return "N/A" if value.nil?

          "#{(value * 100).round(4)}%"
        end
      end
    end
  end
end
