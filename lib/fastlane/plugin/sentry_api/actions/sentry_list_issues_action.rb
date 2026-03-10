require 'fastlane/action'
require_relative '../helper/sentry_api_helper'

module Fastlane
  module Actions
    module SharedValues
      SENTRY_ISSUES = :SENTRY_ISSUES
      SENTRY_ISSUE_COUNT = :SENTRY_ISSUE_COUNT
      SENTRY_ISSUES_STATUS_CODE = :SENTRY_ISSUES_STATUS_CODE
      SENTRY_ISSUES_JSON = :SENTRY_ISSUES_JSON
    end

    # Fetch issues from a Sentry project. Supports filtering by release, query, sort order, etc.
    # Uses the Projects Issues API: GET /api/0/projects/{org}/{project}/issues/
    class SentryListIssuesAction < Action
      class << self
        def run(params)
          auth_token = params[:auth_token]
          org_slug = params[:org_slug]
          project_slug = params[:project_slug]

          query_params = build_query_params(params)

          UI.message("Fetching issues from Sentry project '#{project_slug}'...")

          response = Helper::SentryApiHelper.get_issues(
            auth_token: auth_token,
            org_slug: org_slug,
            project_slug: project_slug,
            params: query_params
          )

          status_code = response[:status]
          json = response[:json]

          unless status_code.between?(200, 299)
            UI.user_error!("Sentry Issues API error #{status_code}: #{response[:body]}")
            return nil
          end

          issues = parse_response(json)
          issue_count = issues.length

          Actions.lane_context[SharedValues::SENTRY_ISSUES_STATUS_CODE] = status_code
          Actions.lane_context[SharedValues::SENTRY_ISSUES_JSON] = json
          Actions.lane_context[SharedValues::SENTRY_ISSUES] = issues
          Actions.lane_context[SharedValues::SENTRY_ISSUE_COUNT] = issue_count

          UI.success("Fetched #{issue_count} issues from '#{project_slug}'")
          issues.first(5).each do |issue|
            UI.message("  #{issue[:short_id]}: #{issue[:title]} (#{issue[:event_count]} events, #{issue[:user_count]} users)")
          end

          { issues: issues, count: issue_count }
        end

        #####################################################
        # @!group Documentation
        #####################################################

        def description
          "Fetch issues from a Sentry project"
        end

        def details
          [
            "Fetches issues from a Sentry project using the Projects Issues API.",
            "Supports filtering by release version, query string, sort order, and pagination.",
            "Useful for comparing issues across releases (e.g. latest vs previous).",
            "",
            "API Documentation: https://docs.sentry.io/api/events/list-a-projects-issues/"
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
            FastlaneCore::ConfigItem.new(key: :project_slug,
                                         env_name: "SENTRY_PROJECT_SLUG",
                                         description: "Sentry project slug (e.g. 'ios', 'android')",
                                         optional: false,
                                         type: String,
                                         verify_block: proc do |value|
                                                         UI.user_error!("No Sentry project slug given, pass using `project_slug: 'ios'`") if value.to_s.empty?
                                                       end),
            FastlaneCore::ConfigItem.new(key: :query,
                                         description: "Sentry search query (e.g. 'is:unresolved', 'is:unresolved release:v1.0')",
                                         optional: true,
                                         default_value: "is:unresolved",
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :sort,
                                         description: "Sort order: 'date', 'new', 'freq', 'priority', 'user', 'trend'",
                                         optional: true,
                                         default_value: "freq",
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :stats_period,
                                         description: "Time window for issue stats (e.g. '7d', '14d', '30d')",
                                         optional: true,
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :per_page,
                                         description: "Number of issues to return (max 100)",
                                         optional: true,
                                         default_value: 25,
                                         type: Integer),
            FastlaneCore::ConfigItem.new(key: :cursor,
                                         description: "Pagination cursor for fetching next page of results",
                                         optional: true,
                                         type: String)
          ]
        end

        def output
          [
            ['SENTRY_ISSUES', 'Array of issue hashes with :id, :short_id, :title, :event_count, :user_count, :first_seen, :last_seen, :level, :status'],
            ['SENTRY_ISSUE_COUNT', 'Number of issues returned'],
            ['SENTRY_ISSUES_STATUS_CODE', 'HTTP status code from the Sentry API'],
            ['SENTRY_ISSUES_JSON', 'Raw JSON response from the Sentry API']
          ]
        end

        def return_value
          "A hash with :issues (array of issue hashes) and :count (number of issues)."
        end

        def authors
          ["crazymanish"]
        end

        def example_code
          [
            '# Fetch unresolved issues sorted by frequency
            result = sentry_list_issues(query: "is:unresolved", sort: "freq", per_page: 10)
            result[:issues].each do |issue|
              UI.message("##{issue[:short_id]}: #{issue[:title]} (#{issue[:event_count]} events)")
            end',

            '# Fetch issues for a specific release
            sentry_list_issues(query: "is:unresolved release:v25.10.0", sort: "freq")',

            '# Fetch new issues in the latest release
            sentry_list_issues(query: "is:unresolved first-release:v25.10.0", sort: "date")'
          ]
        end

        def category
          :misc
        end

        def is_supported?(platform)
          true
        end

        private

        def build_query_params(params)
          query_params = {}

          query_params[:query] = params[:query] if params[:query]
          query_params[:sort] = params[:sort] if params[:sort]
          query_params[:statsPeriod] = params[:stats_period] if params[:stats_period]
          query_params[:per_page] = params[:per_page].to_s if params[:per_page]
          query_params[:cursor] = params[:cursor] if params[:cursor]

          query_params
        end

        def parse_response(json)
          return [] unless json.kind_of?(Array)

          json.map do |issue|
            {
              id: issue['id'],
              short_id: issue['shortId'],
              title: issue['title'],
              culprit: issue['culprit'],
              level: issue['level'],
              status: issue['status'],
              event_count: (issue['count'] || '0').to_i,
              user_count: issue['userCount'] || 0,
              first_seen: issue['firstSeen'],
              last_seen: issue['lastSeen'],
              permalink: issue['permalink'],
              metadata: issue['metadata']
            }
          end
        end
      end
    end
  end
end
