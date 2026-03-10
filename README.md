# sentry_api plugin

[![fastlane Plugin Badge](https://rawcdn.githack.com/fastlane/fastlane/master/fastlane/assets/plugin-badge.svg)](https://rubygems.org/gems/fastlane-plugin-sentry_api)

## Getting Started

This project is a [_fastlane_](https://github.com/fastlane/fastlane) plugin. To get started with `fastlane-plugin-sentry_api`, add it to your project by running:

```bash
fastlane add_plugin sentry_api
```

## About sentry_api

A Fastlane plugin providing reusable actions for querying [Sentry](https://sentry.io) APIs. Built for tracking SLOs (Service Level Objectives) around **availability** (crash-free rates), **latency** (TTID percentiles), and **release issue comparison** — with support for week-over-week and release-over-release analysis.

### Actions

| Action | Description |
|--------|-------------|
| [`sentry_api`](#sentry_api) | Generic GET request to any Sentry API endpoint |
| [`sentry_crash_free_sessions`](#sentry_crash_free_sessions) | Crash-free session & user rates from the Sessions API |
| [`sentry_crash_free_users`](#sentry_crash_free_users) | User-focused crash-free rate (convenience wrapper) |
| [`sentry_ttid_percentiles`](#sentry_ttid_percentiles) | TTID p50/p75/p95 per screen from the Discover API |
| [`sentry_list_issues`](#sentry_list_issues) | Fetch project issues with filtering & sorting |
| [`sentry_slo_report`](#sentry_slo_report) | Comprehensive SLO report orchestrating all the above |

### Environment Variables

Set these once to avoid passing them to every action:

| Variable | Description |
|----------|-------------|
| `SENTRY_AUTH_TOKEN` | Sentry API Bearer auth token |
| `SENTRY_API_SERVER_URL` | Sentry API base URL (default: `https://sentry.io/api/0`) |
| `SENTRY_ORG_SLUG` | Sentry organization slug |
| `SENTRY_PROJECT_ID` | Sentry numeric project ID |
| `SENTRY_PROJECT_SLUG` | Sentry project slug |
| `SENTRY_ENVIRONMENT` | Environment filter (default: `production`) |

---

## Actions

### `sentry_api`

Make a generic GET request to any Sentry REST API endpoint. Use this for endpoints not covered by the specific actions.

**Parameters:**

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `auth_token` | `String` | Yes | `SENTRY_AUTH_TOKEN` | API Bearer auth token |
| `server_url` | `String` | No | `https://sentry.io/api/0` | API base URL |
| `path` | `String` | Yes | — | API endpoint path |
| `params` | `Hash` | No | `{}` | Query parameters (Array values produce repeated keys) |

**Output (SharedValues):** `SENTRY_API_STATUS_CODE`, `SENTRY_API_RESPONSE`, `SENTRY_API_JSON`

**Example:**

```ruby
result = sentry_api(
  path: "/organizations/my-org/sessions/",
  params: { field: ["crash_free_rate(session)"], statsPeriod: "7d", project: "12345" }
)
UI.message("Response: #{result[:json]}")
```

---

### `sentry_crash_free_sessions`

Query crash-free session and user rates from the Sentry Sessions API. Supports aggregate metrics for a time period (week-over-week) and grouped-by-release metrics (release-over-release).

**Parameters:**

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `auth_token` | `String` | Yes | `SENTRY_AUTH_TOKEN` | API Bearer auth token |
| `org_slug` | `String` | Yes | `SENTRY_ORG_SLUG` | Organization slug |
| `project_id` | `String` | Yes | `SENTRY_PROJECT_ID` | Numeric project ID |
| `environment` | `String` | No | `production` | Environment filter |
| `stats_period` | `String` | No | `7d` | Rolling window (`7d`, `14d`, `30d`). Mutually exclusive with `start_date`/`end_date` |
| `start_date` | `String` | No | — | ISO 8601 start date (use with `end_date`) |
| `end_date` | `String` | No | — | ISO 8601 end date (use with `start_date`) |
| `group_by` | `String` | No | — | Group by: `release`, `environment`, or nil for aggregate |
| `per_page` | `Integer` | No | `10` | Number of groups to return (max 100) |
| `order_by` | `String` | No | `-sum(session)` | Sort order for grouped results |

**Output (SharedValues):** `SENTRY_CRASH_FREE_SESSION_RATE`, `SENTRY_CRASH_FREE_USER_RATE`, `SENTRY_TOTAL_SESSIONS`, `SENTRY_TOTAL_USERS`, `SENTRY_SESSION_GROUPS`

**Examples:**

```ruby
# Aggregate crash-free rate for last 7 days
sentry_crash_free_sessions(stats_period: "7d")
rate = lane_context[SharedValues::SENTRY_CRASH_FREE_SESSION_RATE]
UI.message("Crash-free sessions: #{(rate * 100).round(2)}%")

# Grouped by release (release-over-release comparison)
result = sentry_crash_free_sessions(stats_period: "30d", group_by: "release", per_page: 5)
result[:groups].each do |g|
  puts "#{g[:by]['release']}: #{(g[:crash_free_session_rate] * 100).round(2)}%"
end

# Custom date range (for week-over-week comparison)
sentry_crash_free_sessions(
  start_date: "2026-02-24T00:00:00Z",
  end_date: "2026-03-03T00:00:00Z"
)
```

---

### `sentry_crash_free_users`

Convenience action for fetching user-centric crash-free metrics. For full session + user metrics, use `sentry_crash_free_sessions` instead.

**Parameters:**

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `auth_token` | `String` | Yes | `SENTRY_AUTH_TOKEN` | API Bearer auth token |
| `org_slug` | `String` | Yes | `SENTRY_ORG_SLUG` | Organization slug |
| `project_id` | `String` | Yes | `SENTRY_PROJECT_ID` | Numeric project ID |
| `environment` | `String` | No | `production` | Environment filter |
| `stats_period` | `String` | No | `7d` | Rolling window |
| `start_date` | `String` | No | — | ISO 8601 start date |
| `end_date` | `String` | No | — | ISO 8601 end date |

**Output (SharedValues):** `SENTRY_CRASH_FREE_USER_RATE_ONLY`, `SENTRY_TOTAL_USERS_ONLY`

**Example:**

```ruby
sentry_crash_free_users(stats_period: "7d")
rate = lane_context[SharedValues::SENTRY_CRASH_FREE_USER_RATE_ONLY]
UI.message("Crash-free users: #{(rate * 100).round(2)}%")
```

---

### `sentry_ttid_percentiles`

Query TTID (Time to Initial Display) percentiles per screen from the Sentry Events/Discover API. Returns p50, p75, p95 per screen transaction, sorted by load count.

**Parameters:**

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `auth_token` | `String` | Yes | `SENTRY_AUTH_TOKEN` | API Bearer auth token |
| `org_slug` | `String` | Yes | `SENTRY_ORG_SLUG` | Organization slug |
| `project_id` | `String` | Yes | `SENTRY_PROJECT_ID` | Numeric project ID |
| `environment` | `String` | No | `production` | Environment filter |
| `stats_period` | `String` | No | `7d` | Rolling window |
| `start_date` | `String` | No | — | ISO 8601 start date |
| `end_date` | `String` | No | — | ISO 8601 end date |
| `release` | `String` | No | — | Filter by release version |
| `transaction_op` | `String` | No | `ui.load` | Transaction operation filter |
| `per_page` | `Integer` | No | `20` | Number of screens to return (max 100) |
| `sort` | `String` | No | `-count()` | Sort order |

**Output (SharedValues):** `SENTRY_TTID_DATA` (array of `{ transaction:, p50:, p75:, p95:, count: }`)

**Examples:**

```ruby
# Top 10 screens by load count
screens = sentry_ttid_percentiles(stats_period: "7d", per_page: 10)
screens.each do |s|
  UI.message("#{s[:transaction]}: p50=#{s[:p50]}ms p95=#{s[:p95]}ms (#{s[:count]} loads)")
end

# Filter by release
sentry_ttid_percentiles(release: "v25.10.0", stats_period: "14d")

# Custom date range (for week-over-week comparison)
sentry_ttid_percentiles(
  start_date: "2026-02-24T00:00:00Z",
  end_date: "2026-03-03T00:00:00Z"
)
```

---

### `sentry_list_issues`

Fetch issues from a Sentry project. Supports filtering by release version, query string, sort order, and pagination. Useful for comparing issues across releases.

**Parameters:**

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `auth_token` | `String` | Yes | `SENTRY_AUTH_TOKEN` | API Bearer auth token |
| `org_slug` | `String` | Yes | `SENTRY_ORG_SLUG` | Organization slug |
| `project_slug` | `String` | Yes | `SENTRY_PROJECT_SLUG` | Project slug |
| `query` | `String` | No | `is:unresolved` | Sentry search query |
| `sort` | `String` | No | `freq` | Sort: `date`, `new`, `freq`, `priority`, `user`, `trend` |
| `stats_period` | `String` | No | — | Time window for issue stats |
| `per_page` | `Integer` | No | `25` | Number of issues to return (max 100) |
| `cursor` | `String` | No | — | Pagination cursor |

**Output (SharedValues):** `SENTRY_ISSUES` (array of issue hashes), `SENTRY_ISSUE_COUNT`

**Examples:**

```ruby
# Fetch unresolved issues sorted by frequency
result = sentry_list_issues(query: "is:unresolved", sort: "freq", per_page: 10)
result[:issues].each do |issue|
  UI.message("##{issue[:short_id]}: #{issue[:title]} (#{issue[:event_count]} events)")
end

# Issues for a specific release
sentry_list_issues(query: "is:unresolved release:v25.10.0", sort: "freq")

# New issues introduced in a release
sentry_list_issues(query: "is:unresolved first-release:v25.10.0", sort: "date")
```

---

### `sentry_slo_report`

Generate a comprehensive SLO report by orchestrating multiple Sentry API calls. Produces a structured report with:

- **Availability** — Crash-free session/user rates with week-over-week delta
- **Latency** — TTID p50/p75/p95 per screen with week-over-week delta
- **Release comparison** — Release-over-release crash-free rates
- **Issues** — Issue counts and top issues per release (latest vs previous)

Includes target checking with ✅/⚠️ indicators and optional JSON file output.

**Parameters:**

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `auth_token` | `String` | Yes | `SENTRY_AUTH_TOKEN` | API Bearer auth token |
| `org_slug` | `String` | Yes | `SENTRY_ORG_SLUG` | Organization slug |
| `project_id` | `String` | Yes | `SENTRY_PROJECT_ID` | Numeric project ID |
| `project_slug` | `String` | Yes | `SENTRY_PROJECT_SLUG` | Project slug |
| `environment` | `String` | No | `production` | Environment filter |
| `stats_period` | `String` | No | `7d` | Rolling window |
| `crash_free_target` | `Float` | No | `0.998` | Target crash-free session rate (e.g. 0.998 = 99.8%) |
| `ttid_p95_target_ms` | `Integer` | No | `1000` | Target TTID p95 in milliseconds |
| `compare_weeks` | `Boolean` | No | `true` | Include week-over-week comparison |
| `compare_releases` | `Boolean` | No | `true` | Include release-over-release comparison |
| `current_release` | `String` | No | — | Current release version for issue comparison |
| `previous_release` | `String` | No | — | Previous release version for issue comparison |
| `release_count` | `Integer` | No | `5` | Number of releases to compare |
| `ttid_screen_count` | `Integer` | No | `10` | Number of top screens in TTID report |
| `issue_count` | `Integer` | No | `10` | Number of top issues per release |
| `output_json` | `String` | No | — | Path to write JSON report file |

**Output (SharedValues):** `SENTRY_SLO_REPORT` (complete hash with `:availability`, `:latency`, `:issues`)

**Examples:**

```ruby
# Full SLO report with WoW & RoR comparison
sentry_slo_report(
  crash_free_target: 0.998,
  ttid_p95_target_ms: 1000,
  compare_weeks: true,
  compare_releases: true,
  current_release: "v25.10.0",
  previous_release: "v25.9.0",
  output_json: "slo_report.json"
)

# Quick availability check only
report = sentry_slo_report(
  compare_weeks: true,
  compare_releases: false
)
rate = report[:availability][:current][:crash_free_session_rate]
UI.important("Crash-free: #{(rate * 100).round(2)}%")
```

---

## Example Fastfile

Check out the [example `Fastfile`](fastlane/Fastfile) for usage examples. Try it by cloning the repo, running `fastlane install_plugins` and `bundle exec fastlane test`.

```ruby
lane :availability_check do
  sentry_crash_free_sessions(stats_period: "7d")

  rate = lane_context[SharedValues::SENTRY_CRASH_FREE_SESSION_RATE]
  UI.important("Crash-free session rate: #{(rate * 100).round(2)}%")
end

lane :slo_report do
  sentry_slo_report(
    crash_free_target: 0.998,
    ttid_p95_target_ms: 1000,
    current_release: "v25.10.0",
    previous_release: "v25.9.0",
    output_json: "slo_report.json"
  )
end
```

## Run tests for this plugin

To run both the tests, and code style validation, run

```
rake
```

To automatically fix many of the styling issues, use
```
rubocop -a
```

## Issues and Feedback

For any other issues and feedback about this plugin, please submit it to this repository.

## Troubleshooting

If you have trouble using plugins, check out the [Plugins Troubleshooting](https://docs.fastlane.tools/plugins/plugins-troubleshooting/) guide.

## Using _fastlane_ Plugins

For more information about how the `fastlane` plugin system works, check out the [Plugins documentation](https://docs.fastlane.tools/plugins/create-plugin/).

## About _fastlane_

_fastlane_ is the easiest way to automate beta deployments and releases for your iOS and Android apps. To learn more, check out [fastlane.tools](https://fastlane.tools).
