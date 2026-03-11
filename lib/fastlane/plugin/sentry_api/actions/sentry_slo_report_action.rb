require 'fastlane/action'
require 'json'
require 'time'
require_relative '../helper/sentry_api_helper'

module Fastlane
  module Actions
    module SharedValues
      SENTRY_SLO_REPORT = :SENTRY_SLO_REPORT
    end

    # Orchestrator action that produces a comprehensive SLO report by querying
    # crash-free rates (availability), TTID percentiles (latency), and release issues.
    # Supports week-over-week, release-over-release comparisons, and issues diff.
    class SentrySloReportAction < Action
      class << self
        def run(params)
          auth_token = params[:auth_token]
          org_slug = params[:org_slug]
          project_id = params[:project_id]
          project_slug = params[:project_slug]
          environment = params[:environment]
          stats_period = params[:stats_period]
          days = parse_days(stats_period)

          report = {
            generated_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
            period: stats_period,
            environment: environment,
            availability: {},
            latency: {},
            issues: {}
          }

          # ── AVAILABILITY (Crash-Free Sessions) ──────────────────────────
          UI.header("Availability (Crash-Free Sessions)")

          report[:availability][:current] = fetch_crash_free(
            auth_token: auth_token, org_slug: org_slug, project_id: project_id,
            environment: environment, stats_period: stats_period
          )
          log_availability("Current #{stats_period}", report[:availability][:current], params[:crash_free_target])

          if params[:compare_weeks]
            prev_dates = previous_period_dates(days)
            report[:availability][:previous] = fetch_crash_free(
              auth_token: auth_token, org_slug: org_slug, project_id: project_id,
              environment: environment,
              start_date: prev_dates[:start], end_date: prev_dates[:end]
            )
            log_availability("Previous #{stats_period}", report[:availability][:previous], params[:crash_free_target])

            report[:availability][:delta] = compute_availability_delta(
              report[:availability][:current], report[:availability][:previous]
            )
            log_delta(report[:availability][:delta])
          end

          report[:availability][:target] = params[:crash_free_target]
          report[:availability][:current_meets_target] = meets_target?(
            report[:availability][:current][:crash_free_session_rate], params[:crash_free_target]
          )

          if params[:compare_releases]
            report[:availability][:releases] = fetch_crash_free_by_release(
              auth_token: auth_token, org_slug: org_slug, project_id: project_id,
              environment: environment, stats_period: stats_period,
              per_page: params[:release_count]
            )
            log_releases(report[:availability][:releases], params[:crash_free_target])
          end

          # ── LATENCY (TTID Percentiles) ──────────────────────────────────
          UI.header("Latency (TTID Percentiles)")

          report[:latency][:current] = fetch_ttid(
            auth_token: auth_token, org_slug: org_slug, project_id: project_id,
            environment: environment, stats_period: stats_period,
            per_page: params[:ttid_screen_count]
          )
          log_ttid("Current #{stats_period}", report[:latency][:current], params[:ttid_p95_target_ms])

          # Overall/aggregate TTID
          report[:latency][:overall] = fetch_ttid_overall(
            auth_token: auth_token, org_slug: org_slug, project_id: project_id,
            environment: environment, stats_period: stats_period
          )
          log_ttid_overall("Current #{stats_period}", report[:latency][:overall], params[:ttid_p95_target_ms])

          if params[:compare_weeks]
            prev_dates = previous_period_dates(days)
            report[:latency][:previous] = fetch_ttid(
              auth_token: auth_token, org_slug: org_slug, project_id: project_id,
              environment: environment,
              start_date: prev_dates[:start], end_date: prev_dates[:end],
              per_page: params[:ttid_screen_count]
            )
            log_ttid("Previous #{stats_period}", report[:latency][:previous], params[:ttid_p95_target_ms])

            report[:latency][:overall_previous] = fetch_ttid_overall(
              auth_token: auth_token, org_slug: org_slug, project_id: project_id,
              environment: environment,
              start_date: prev_dates[:start], end_date: prev_dates[:end]
            )
            log_ttid_overall("Previous #{stats_period}", report[:latency][:overall_previous], params[:ttid_p95_target_ms])
          end

          report[:latency][:target_p95_ms] = params[:ttid_p95_target_ms]

          # ── LATENCY (App Launch) ────────────────────────────────────────
          UI.header("Latency (App Launch)")

          report[:latency][:app_launch] = fetch_app_launch(
            auth_token: auth_token, org_slug: org_slug, project_id: project_id,
            environment: environment, stats_period: stats_period
          )
          log_app_launch("Current #{stats_period}", report[:latency][:app_launch], params[:app_launch_p95_target_ms])

          if params[:compare_weeks]
            prev_dates = previous_period_dates(days)
            report[:latency][:app_launch_previous] = fetch_app_launch(
              auth_token: auth_token, org_slug: org_slug, project_id: project_id,
              environment: environment,
              start_date: prev_dates[:start], end_date: prev_dates[:end]
            )
            log_app_launch("Previous #{stats_period}", report[:latency][:app_launch_previous], params[:app_launch_p95_target_ms])
          end

          report[:latency][:app_launch_p95_target_ms] = params[:app_launch_p95_target_ms]

          # ── TOP CRASH ISSUES ────────────────────────────────────────────
          UI.header("Top Crash Issues")

          report[:issues][:top_crashes] = fetch_top_crash_issues(
            auth_token: auth_token, org_slug: org_slug, project_slug: project_slug,
            stats_period: stats_period, per_page: params[:crash_issue_count]
          )
          log_top_crashes(report[:issues][:top_crashes])

          # ── ISSUES (Release Comparison) ─────────────────────────────────
          if params[:current_release]
            UI.header("Issues (Release Comparison)")

            report[:issues][:current_release] = fetch_issues_for_release(
              auth_token: auth_token, org_slug: org_slug, project_slug: project_slug,
              release: params[:current_release], per_page: params[:issue_count]
            )
            log_issues(params[:current_release], report[:issues][:current_release])

            if params[:previous_release]
              report[:issues][:previous_release] = fetch_issues_for_release(
                auth_token: auth_token, org_slug: org_slug, project_slug: project_slug,
                release: params[:previous_release], per_page: params[:issue_count]
              )
              log_issues(params[:previous_release], report[:issues][:previous_release])
            end
          end

          # ── OUTPUT ──────────────────────────────────────────────────────
          if params[:output_json]
            File.write(params[:output_json], JSON.pretty_generate(report))
            UI.success("SLO report JSON written to #{params[:output_json]}")
          end

          Actions.lane_context[SharedValues::SENTRY_SLO_REPORT] = report

          print_summary(report, params)

          report
        end

        #####################################################
        # @!group Documentation
        #####################################################

        def description
          "Generate a comprehensive SLO report with availability, latency, and issue comparison"
        end

        def details
          [
            "Orchestrates multiple Sentry API calls to produce a comprehensive SLO report including:",
            "  - Crash-free session/user rates (availability) with week-over-week delta",
            "  - Release-over-release crash-free rate comparison",
            "  - TTID p50/p75/p95 per screen (latency) with week-over-week delta",
            "  - Overall/aggregate TTID percentiles across all screens",
            "  - App launch latency (cold start & warm start) percentiles",
            "  - Issue counts and top issues per release (latest vs previous)",
            "",
            "Outputs a structured hash to lane_context and optionally writes JSON to a file."
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
                                                         UI.user_error!("No Sentry auth token given") if value.to_s.empty?
                                                       end),
            FastlaneCore::ConfigItem.new(key: :org_slug,
                                         env_name: "SENTRY_ORG_SLUG",
                                         description: "Sentry organization slug",
                                         optional: false,
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :project_id,
                                         env_name: "SENTRY_PROJECT_ID",
                                         description: "Sentry numeric project ID (for Sessions & Events APIs)",
                                         optional: false,
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :project_slug,
                                         env_name: "SENTRY_PROJECT_SLUG",
                                         description: "Sentry project slug (for Issues API)",
                                         optional: false,
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :environment,
                                         env_name: "SENTRY_ENVIRONMENT",
                                         description: "Environment filter",
                                         optional: true,
                                         default_value: "production",
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :stats_period,
                                         description: "Rolling time window (e.g. '7d', '14d')",
                                         optional: true,
                                         default_value: "7d",
                                         type: String),
            # ── Targets ──
            FastlaneCore::ConfigItem.new(key: :crash_free_target,
                                         description: "Target crash-free session rate (e.g. 0.998 = 99.8%)",
                                         optional: true,
                                         default_value: 0.998,
                                         type: Float),
            FastlaneCore::ConfigItem.new(key: :ttid_p95_target_ms,
                                         description: "Target TTID p95 in milliseconds",
                                         optional: true,
                                         default_value: 1000,
                                         type: Integer),
            FastlaneCore::ConfigItem.new(key: :app_launch_p95_target_ms,
                                         description: "Target app launch (cold start) p95 in milliseconds",
                                         optional: true,
                                         default_value: 2000,
                                         type: Integer),
            # ── Comparison flags ──
            FastlaneCore::ConfigItem.new(key: :compare_weeks,
                                         description: "Include week-over-week comparison",
                                         optional: true,
                                         default_value: true,
                                         type: Fastlane::Boolean),
            FastlaneCore::ConfigItem.new(key: :compare_releases,
                                         description: "Include release-over-release comparison",
                                         optional: true,
                                         default_value: true,
                                         type: Fastlane::Boolean),
            # ── Release versions ──
            FastlaneCore::ConfigItem.new(key: :current_release,
                                         description: "Current release version for issue comparison (e.g. 'v25.10.0')",
                                         optional: true,
                                         type: String),
            FastlaneCore::ConfigItem.new(key: :previous_release,
                                         description: "Previous release version for issue comparison (e.g. 'v25.9.0')",
                                         optional: true,
                                         type: String),
            # ── Limits ──
            FastlaneCore::ConfigItem.new(key: :release_count,
                                         description: "Number of releases to compare",
                                         optional: true,
                                         default_value: 5,
                                         type: Integer),
            FastlaneCore::ConfigItem.new(key: :ttid_screen_count,
                                         description: "Number of top screens to include in TTID report",
                                         optional: true,
                                         default_value: 10,
                                         type: Integer),
            FastlaneCore::ConfigItem.new(key: :issue_count,
                                         description: "Number of top issues to include per release",
                                         optional: true,
                                         default_value: 10,
                                         type: Integer),
            FastlaneCore::ConfigItem.new(key: :crash_issue_count,
                                         description: "Number of top crash issues to include",
                                         optional: true,
                                         default_value: 5,
                                         type: Integer),
            # ── Output ──
            FastlaneCore::ConfigItem.new(key: :output_json,
                                         description: "Path to write JSON report file (optional)",
                                         optional: true,
                                         type: String)
          ]
        end

        def output
          [
            ['SENTRY_SLO_REPORT', 'Complete SLO report hash with :availability, :latency, :issues sections']
          ]
        end

        def return_value
          "A hash with :availability, :latency, and :issues sections containing all SLO data."
        end

        def authors
          ["crazymanish"]
        end

        def example_code
          [
            '# Full SLO report with WoW & RoR comparison
            sentry_slo_report(
              crash_free_target: 0.998,
              ttid_p95_target_ms: 1000,
              compare_weeks: true,
              compare_releases: true,
              current_release: "v25.10.0",
              previous_release: "v25.9.0",
              output_json: "slo_report.json"
            )',

            '# Quick availability check only
            report = sentry_slo_report(
              compare_weeks: true,
              compare_releases: false
            )
            rate = report[:availability][:current][:crash_free_session_rate]
            UI.important("Crash-free: #{(rate * 100).round(2)}%")'
          ]
        end

        def category
          :misc
        end

        def is_supported?(platform)
          true
        end

        private

        # ── Data Fetchers ─────────────────────────────────────────────────

        def fetch_crash_free(auth_token:, org_slug:, project_id:, environment:, stats_period: nil, start_date: nil, end_date: nil)
          params = {
            field: ['crash_free_rate(session)', 'crash_free_rate(user)', 'sum(session)', 'count_unique(user)'],
            project: project_id.to_s,
            includeSeries: '0'
          }

          if start_date && end_date
            params[:start] = start_date
            params[:end] = end_date
          else
            params[:statsPeriod] = stats_period
          end

          params[:environment] = environment if environment

          response = Helper::SentryApiHelper.get_sessions(auth_token: auth_token, org_slug: org_slug, params: params)

          unless response[:status].between?(200, 299)
            UI.error("Sentry Sessions API error #{response[:status]}: #{response[:body]}")
            return empty_crash_free
          end

          totals = response[:json]&.dig('groups', 0, 'totals') || {}

          {
            crash_free_session_rate: totals['crash_free_rate(session)'],
            crash_free_user_rate: totals['crash_free_rate(user)'],
            total_sessions: totals['sum(session)'],
            total_users: totals['count_unique(user)']
          }
        end

        def fetch_crash_free_by_release(auth_token:, org_slug:, project_id:, environment:, stats_period:, per_page:)
          params = {
            field: ['crash_free_rate(session)', 'crash_free_rate(user)', 'sum(session)'],
            groupBy: 'release',
            project: project_id.to_s,
            statsPeriod: stats_period,
            per_page: per_page.to_s,
            orderBy: '-sum(session)',
            includeSeries: '0'
          }
          params[:environment] = environment if environment

          response = Helper::SentryApiHelper.get_sessions(auth_token: auth_token, org_slug: org_slug, params: params)

          unless response[:status].between?(200, 299)
            UI.error("Sentry Sessions API error #{response[:status]}: #{response[:body]}")
            return []
          end

          groups = response[:json]&.dig('groups') || []
          groups.map do |group|
            totals = group['totals'] || {}
            {
              release: group.dig('by', 'release'),
              crash_free_session_rate: totals['crash_free_rate(session)'],
              crash_free_user_rate: totals['crash_free_rate(user)'],
              total_sessions: totals['sum(session)']
            }
          end
        end

        def fetch_ttid(auth_token:, org_slug:, project_id:, environment:, stats_period: nil, start_date: nil, end_date: nil, per_page: 10)
          fields = [
            'transaction',
            'p50(measurements.time_to_initial_display)',
            'p75(measurements.time_to_initial_display)',
            'p95(measurements.time_to_initial_display)',
            'count()'
          ]

          params = {
            dataset: 'metrics',
            field: fields,
            project: project_id.to_s,
            query: 'event.type:transaction transaction.op:ui.load',
            sort: '-count()',
            per_page: per_page.to_s
          }

          if start_date && end_date
            params[:start] = start_date
            params[:end] = end_date
          else
            params[:statsPeriod] = stats_period
          end

          params[:environment] = environment if environment

          response = Helper::SentryApiHelper.get_events(auth_token: auth_token, org_slug: org_slug, params: params)

          unless response[:status].between?(200, 299)
            UI.error("Sentry Events API error #{response[:status]}: #{response[:body]}")
            return []
          end

          data = response[:json]&.dig('data') || []
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

        def fetch_ttid_overall(auth_token:, org_slug:, project_id:, environment:, stats_period: nil, start_date: nil, end_date: nil)
          fields = [
            'p50(measurements.time_to_initial_display)',
            'p75(measurements.time_to_initial_display)',
            'p95(measurements.time_to_initial_display)',
            'count()'
          ]

          params = {
            dataset: 'metrics',
            field: fields,
            project: project_id.to_s,
            query: 'event.type:transaction transaction.op:ui.load',
            per_page: '1'
          }

          if start_date && end_date
            params[:start] = start_date
            params[:end] = end_date
          else
            params[:statsPeriod] = stats_period
          end

          params[:environment] = environment if environment

          response = Helper::SentryApiHelper.get_events(auth_token: auth_token, org_slug: org_slug, params: params)

          unless response[:status].between?(200, 299)
            UI.error("Sentry Events API error #{response[:status]}: #{response[:body]}")
            return empty_ttid_overall
          end

          row = response[:json]&.dig('data', 0) || {}
          {
            p50: round_ms(row['p50(measurements.time_to_initial_display)']),
            p75: round_ms(row['p75(measurements.time_to_initial_display)']),
            p95: round_ms(row['p95(measurements.time_to_initial_display)']),
            count: row['count()']
          }
        end

        def fetch_app_launch(auth_token:, org_slug:, project_id:, environment:, stats_period: nil, start_date: nil, end_date: nil)
          result = {}

          [:cold, :warm].each do |start_type|
            measurement = start_type == :cold ? 'app_start_cold' : 'app_start_warm'

            fields = [
              "p50(measurements.#{measurement})",
              "p75(measurements.#{measurement})",
              "p95(measurements.#{measurement})",
              'count()'
            ]

            params = {
              dataset: 'metrics',
              field: fields,
              project: project_id.to_s,
              query: "event.type:transaction has:measurements.#{measurement}",
              per_page: '1'
            }

            if start_date && end_date
              params[:start] = start_date
              params[:end] = end_date
            else
              params[:statsPeriod] = stats_period
            end

            params[:environment] = environment if environment

            response = Helper::SentryApiHelper.get_events(auth_token: auth_token, org_slug: org_slug, params: params)

            if response[:status].between?(200, 299)
              row = response[:json]&.dig('data', 0) || {}
              result[start_type] = {
                p50: round_ms(row["p50(measurements.#{measurement})"]),
                p75: round_ms(row["p75(measurements.#{measurement})"]),
                p95: round_ms(row["p95(measurements.#{measurement})"]),
                count: row['count()']
              }
            else
              UI.error("Sentry Events API error #{response[:status]} for #{start_type} start: #{response[:body]}")
              result[start_type] = { p50: nil, p75: nil, p95: nil, count: nil }
            end
          end

          result
        end

        # Map a generic stats_period to the closest value the Issues API accepts ('24h' or '14d').
        def issues_api_stats_period(stats_period)
          return '24h' if stats_period == '24h'

          # Anything longer than 24h → use 14d (the only other accepted bucket)
          '14d'
        end

        def fetch_top_crash_issues(auth_token:, org_slug:, project_slug:, stats_period:, per_page:)
          response = Helper::SentryApiHelper.get_issues(
            auth_token: auth_token,
            org_slug: org_slug,
            project_slug: project_slug,
            params: {
              query: 'is:unresolved issue.category:error error.unhandled:true',
              sort: 'freq',
              statsPeriod: issues_api_stats_period(stats_period),
              per_page: per_page.to_s
            }
          )

          unless response[:status].between?(200, 299)
            UI.error("Sentry Issues API error #{response[:status]}: #{response[:body]}")
            return []
          end

          issues_data = response[:json] || []
          issues_data.first(per_page).map do |issue|
            {
              id: issue['id'],
              short_id: issue['shortId'],
              title: issue['title'],
              event_count: (issue['count'] || '0').to_i,
              user_count: issue['userCount'] || 0,
              level: issue['level'],
              first_seen: issue['firstSeen'],
              last_seen: issue['lastSeen']
            }
          end
        end

        def fetch_issues_for_release(auth_token:, org_slug:, project_slug:, release:, per_page:)
          response = Helper::SentryApiHelper.get_issues(
            auth_token: auth_token,
            org_slug: org_slug,
            project_slug: project_slug,
            params: {
              query: "is:unresolved release:#{release}",
              sort: 'freq',
              per_page: per_page.to_s
            }
          )

          unless response[:status].between?(200, 299)
            UI.error("Sentry Issues API error #{response[:status]}: #{response[:body]}")
            return { version: release, count: 0, issues: [] }
          end

          issues_data = response[:json] || []
          issues = issues_data.map do |issue|
            {
              id: issue['id'],
              short_id: issue['shortId'],
              title: issue['title'],
              event_count: (issue['count'] || '0').to_i,
              user_count: issue['userCount'] || 0,
              level: issue['level'],
              first_seen: issue['firstSeen'],
              last_seen: issue['lastSeen']
            }
          end

          { version: release, count: issues.length, issues: issues }
        end

        # ── Date Utilities ────────────────────────────────────────────────

        def parse_days(stats_period)
          match = stats_period.match(/^(\d+)d$/)
          UI.user_error!("Invalid stats_period format '#{stats_period}'. Use format like '7d', '14d'.") unless match

          match[1].to_i
        end

        def previous_period_dates(days)
          now = Time.now.utc
          period_end = now - (days * 86_400)
          period_start = now - (2 * days * 86_400)

          {
            start: period_start.strftime('%Y-%m-%dT%H:%M:%SZ'),
            end: period_end.strftime('%Y-%m-%dT%H:%M:%SZ')
          }
        end

        # ── Computation Helpers ───────────────────────────────────────────

        def compute_availability_delta(current, previous)
          return {} unless current && previous

          {
            crash_free_session_rate: safe_delta(current[:crash_free_session_rate], previous[:crash_free_session_rate]),
            crash_free_user_rate: safe_delta(current[:crash_free_user_rate], previous[:crash_free_user_rate])
          }
        end

        def safe_delta(current_value, previous_value)
          return nil if current_value.nil? || previous_value.nil?

          (current_value - previous_value).round(6)
        end

        def meets_target?(value, target)
          return false if value.nil? || target.nil?

          value >= target
        end

        def empty_crash_free
          { crash_free_session_rate: nil, crash_free_user_rate: nil, total_sessions: nil, total_users: nil }
        end

        def empty_ttid_overall
          { p50: nil, p75: nil, p95: nil, count: nil }
        end

        def round_ms(value)
          return nil if value.nil?

          value.round(1)
        end

        # ── Logging Helpers ───────────────────────────────────────────────

        def log_availability(label, data, target)
          rate = data[:crash_free_session_rate]
          indicator = if rate && target
                        rate >= target ? "✅" : "⚠️"
                      else
                        ""
                      end
          UI.message("  #{label}: #{format_pct(rate)} #{indicator} (target: #{format_pct(target)})")
          UI.message("    Sessions: #{data[:total_sessions]}, Users: #{data[:total_users]}")
        end

        def log_delta(delta)
          session_delta = delta[:crash_free_session_rate]
          sign = session_delta && session_delta >= 0 ? "+" : ""
          UI.message("  Delta: #{sign}#{format_pct(session_delta)}")
        end

        def log_releases(releases, target)
          UI.message("  Release-over-Release:")
          releases.each do |r|
            rate = r[:crash_free_session_rate]
            indicator = if rate && target
                          rate >= target ? "✅" : "⚠️"
                        else
                          ""
                        end
            UI.message("    #{r[:release]}: #{format_pct(rate)} #{indicator}")
          end
        end

        def log_ttid(label, screens, target_p95)
          UI.message("  #{label}: #{screens.length} screens")
          screens.first(5).each do |s|
            indicator = if s[:p95] && target_p95
                          s[:p95] <= target_p95 ? "✅" : "⚠️"
                        else
                          ""
                        end
            UI.message("    #{s[:transaction]}: p50=#{s[:p50]}ms p75=#{s[:p75]}ms p95=#{s[:p95]}ms (#{s[:count]} loads) #{indicator}")
          end
        end

        def log_ttid_overall(label, overall, target_p95)
          return unless overall

          indicator = if overall[:p95] && target_p95
                        overall[:p95] <= target_p95 ? "✅" : "⚠️"
                      else
                        ""
                      end
          UI.message("  #{label} (Overall): p50=#{overall[:p50]}ms p75=#{overall[:p75]}ms p95=#{overall[:p95]}ms (#{overall[:count]} loads) #{indicator}")
        end

        def log_app_launch(label, app_launch, target_p95)
          return unless app_launch

          [:cold, :warm].each do |start_type|
            data = app_launch[start_type]
            next unless data

            type_label = start_type == :cold ? 'Cold start' : 'Warm start'
            if data[:p50]
              indicator = if data[:p95] && target_p95
                            data[:p95] <= target_p95 ? "✅" : "⚠️"
                          else
                            ""
                          end
              UI.message("  #{label} #{type_label}: p50=#{data[:p50]}ms p75=#{data[:p75]}ms p95=#{data[:p95]}ms (#{data[:count]} launches) #{indicator}")
            else
              UI.message("  #{label} #{type_label}: no data")
            end
          end
        end

        def log_top_crashes(crashes)
          if crashes.empty?
            UI.message("  No crash issues found")
            return
          end

          UI.message("  Top #{crashes.length} crash issues:")
          crashes.each_with_index do |issue, idx|
            UI.message("    #{idx + 1}. #{issue[:short_id]}: #{issue[:title]} (#{issue[:event_count]} events, #{issue[:user_count]} users)")
          end
        end

        def log_issues(release, data)
          UI.message("  #{release}: #{data[:count]} unresolved issues")
          data[:issues].first(3).each_with_index do |issue, idx|
            UI.message("    #{idx + 1}. #{issue[:short_id]}: #{issue[:title]} (#{issue[:event_count]} events, #{issue[:user_count]} users)")
          end
        end

        def print_summary(report, params)
          UI.message("")
          UI.header("SLO Report Summary")

          # Availability
          current_rate = report.dig(:availability, :current, :crash_free_session_rate)
          target = params[:crash_free_target]
          indicator = if current_rate && target
                        current_rate >= target ? "✅" : "⚠️"
                      else
                        ""
                      end
          UI.message("Crash-free sessions: #{format_pct(current_rate)} #{indicator} (target: #{format_pct(target)})")

          if report.dig(:availability, :delta)
            delta = report[:availability][:delta][:crash_free_session_rate]
            sign = delta && delta >= 0 ? "+" : ""
            UI.message("Week-over-week delta: #{sign}#{format_pct(delta)}")
          end

          # Latency - Overall TTID
          overall = report.dig(:latency, :overall)
          if overall && overall[:p95]
            target_p95 = params[:ttid_p95_target_ms]
            indicator = if target_p95
                          overall[:p95] <= target_p95 ? "✅" : "⚠️"
                        else
                          ""
                        end
            UI.message("TTID overall p95: #{overall[:p95]}ms #{indicator} (target: #{target_p95}ms)")
            UI.message("TTID overall p50: #{overall[:p50]}ms · p75: #{overall[:p75]}ms (#{overall[:count]} loads)")
          end

          # Latency - Per-screen TTID
          screens = report.dig(:latency, :current) || []
          if screens.any?
            UI.message("TTID top screens: #{screens.length} measured")
          end

          # Latency - App Launch
          app_launch = report.dig(:latency, :app_launch)
          if app_launch
            cold = app_launch[:cold]
            warm = app_launch[:warm]
            launch_target = params[:app_launch_p95_target_ms]

            if cold && cold[:p95]
              indicator = if launch_target
                            cold[:p95] <= launch_target ? "✅" : "⚠️"
                          else
                            ""
                          end
              UI.message("Cold start p95: #{cold[:p95]}ms #{indicator} (target: #{launch_target}ms)")
            end

            if warm && warm[:p95]
              UI.message("Warm start p95: #{warm[:p95]}ms")
            end
          end

          # Top Crash Issues
          top_crashes = report.dig(:issues, :top_crashes) || []
          if top_crashes.any?
            UI.message("Top crash issues (#{top_crashes.length}):")
            top_crashes.each_with_index do |issue, idx|
              UI.message("  #{idx + 1}. #{issue[:short_id]} \u2014 #{issue[:title]} (#{issue[:event_count]} events, #{issue[:user_count]} users)")
            end
          end

          # Issues
          if report.dig(:issues, :current_release)
            current_issues = report[:issues][:current_release]
            UI.message("Issues in #{current_issues[:version]}: #{current_issues[:count]}")
            if report.dig(:issues, :previous_release)
              prev_issues = report[:issues][:previous_release]
              UI.message("Issues in #{prev_issues[:version]}: #{prev_issues[:count]}")
            end
          end

          UI.success("SLO report generated at #{report[:generated_at]}")
        end

        def format_pct(value)
          return "N/A" if value.nil?

          "#{(value * 100).round(4)}%"
        end
      end
    end
  end
end
