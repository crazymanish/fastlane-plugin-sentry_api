describe Fastlane::Actions::SentrySloReportAction do
  let(:auth_token) { 'test-token' }
  let(:org_slug) { 'test-org' }
  let(:project_id) { '12345' }
  let(:project_slug) { 'ios' }

  # ── Mock API responses ─────────────────────────────────────────────

  let(:sessions_response) do
    {
      status: 200,
      body: '{}',
      json: {
        'groups' => [
          {
            'by' => {},
            'totals' => {
              'crash_free_rate(session)' => 0.9974,
              'crash_free_rate(user)' => 0.9981,
              'sum(session)' => 1_250_000,
              'count_unique(user)' => 450_000
            }
          }
        ]
      }
    }
  end

  let(:previous_sessions_response) do
    {
      status: 200,
      body: '{}',
      json: {
        'groups' => [
          {
            'by' => {},
            'totals' => {
              'crash_free_rate(session)' => 0.9968,
              'crash_free_rate(user)' => 0.9975,
              'sum(session)' => 1_200_000,
              'count_unique(user)' => 440_000
            }
          }
        ]
      }
    }
  end

  let(:grouped_sessions_response) do
    {
      status: 200,
      body: '{}',
      json: {
        'groups' => [
          {
            'by' => { 'release' => 'v25.10.0' },
            'totals' => {
              'crash_free_rate(session)' => 0.9981,
              'crash_free_rate(user)' => 0.9991,
              'sum(session)' => 500_000
            }
          },
          {
            'by' => { 'release' => 'v25.9.0' },
            'totals' => {
              'crash_free_rate(session)' => 0.9972,
              'crash_free_rate(user)' => 0.9985,
              'sum(session)' => 750_000
            }
          }
        ]
      }
    }
  end

  let(:ttid_response) do
    {
      status: 200,
      body: '{}',
      json: {
        'data' => [
          {
            'transaction' => 'MainViewController',
            'p50(measurements.time_to_initial_display)' => 320.0,
            'p75(measurements.time_to_initial_display)' => 485.0,
            'p95(measurements.time_to_initial_display)' => 890.0,
            'count()' => 125_000
          },
          {
            'transaction' => 'LotDetailViewController',
            'p50(measurements.time_to_initial_display)' => 410.0,
            'p75(measurements.time_to_initial_display)' => 620.0,
            'p95(measurements.time_to_initial_display)' => 1100.0,
            'count()' => 98_000
          }
        ]
      }
    }
  end

  let(:issues_response) do
    {
      status: 200,
      body: '[]',
      json: [
        {
          'id' => '111',
          'shortId' => 'MBA-1234',
          'title' => 'NSInternalInconsistencyException',
          'count' => '450',
          'userCount' => 120,
          'level' => 'error',
          'firstSeen' => '2026-03-05T10:00:00Z',
          'lastSeen' => '2026-03-10T08:00:00Z'
        }
      ]
    }
  end

  # ── Tests ──────────────────────────────────────────────────────────

  describe '#run full report' do
    before do
      # Sessions API: current, previous, and grouped
      call_count = 0
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions) do |**args|
        call_count += 1
        if args[:params][:groupBy] == 'release'
          grouped_sessions_response
        elsif args[:params][:start]
          previous_sessions_response
        else
          sessions_response
        end
      end

      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_events).and_return(ttid_response)
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_issues).and_return(issues_response)
    end

    it 'produces a complete SLO report' do
      report = Fastlane::Actions::SentrySloReportAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        project_slug: project_slug,
        environment: 'production',
        stats_period: '7d',
        crash_free_target: 0.998,
        ttid_p95_target_ms: 1000,
        compare_weeks: true,
        compare_releases: true,
        current_release: 'v25.10.0',
        previous_release: 'v25.9.0',
        release_count: 5,
        ttid_screen_count: 10,
        issue_count: 10
      )

      # Verify report structure
      expect(report).to be_a(Hash)
      expect(report[:generated_at]).not_to be_nil
      expect(report[:period]).to eq('7d')
      expect(report[:environment]).to eq('production')

      # Availability - current
      current = report[:availability][:current]
      expect(current[:crash_free_session_rate]).to eq(0.9974)
      expect(current[:crash_free_user_rate]).to eq(0.9981)
      expect(current[:total_sessions]).to eq(1_250_000)

      # Availability - previous (WoW)
      previous = report[:availability][:previous]
      expect(previous[:crash_free_session_rate]).to eq(0.9968)

      # Availability - delta
      delta = report[:availability][:delta]
      expect(delta[:crash_free_session_rate]).to eq(0.0006)

      # Availability - target
      expect(report[:availability][:target]).to eq(0.998)
      expect(report[:availability][:current_meets_target]).to eq(false) # 0.9974 < 0.998

      # Availability - releases
      releases = report[:availability][:releases]
      expect(releases).to be_an(Array)
      expect(releases.length).to eq(2)
      expect(releases[0][:release]).to eq('v25.10.0')
      expect(releases[0][:crash_free_session_rate]).to eq(0.9981)

      # Latency - current
      screens = report[:latency][:current]
      expect(screens.length).to eq(2)
      expect(screens[0][:transaction]).to eq('MainViewController')
      expect(screens[0][:p95]).to eq(890.0)

      # Latency - previous
      expect(report[:latency][:previous]).to be_an(Array)

      # Latency - target
      expect(report[:latency][:target_p95_ms]).to eq(1000)

      # Issues - current release
      current_issues = report[:issues][:current_release]
      expect(current_issues[:version]).to eq('v25.10.0')
      expect(current_issues[:count]).to eq(1)
      expect(current_issues[:issues][0][:short_id]).to eq('MBA-1234')

      # Issues - previous release
      prev_issues = report[:issues][:previous_release]
      expect(prev_issues[:version]).to eq('v25.9.0')
    end

    it 'stores report in lane context' do
      Fastlane::Actions::SentrySloReportAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        project_slug: project_slug,
        environment: 'production',
        stats_period: '7d',
        crash_free_target: 0.998,
        ttid_p95_target_ms: 1000,
        compare_weeks: true,
        compare_releases: true,
        current_release: 'v25.10.0',
        previous_release: 'v25.9.0'
      )

      report = Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_SLO_REPORT]
      expect(report).to be_a(Hash)
      expect(report[:availability]).not_to be_nil
      expect(report[:latency]).not_to be_nil
      expect(report[:issues]).not_to be_nil
    end
  end

  describe '#run with JSON output' do
    before do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).and_return(sessions_response)
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_events).and_return(ttid_response)
    end

    it 'writes JSON report to file' do
      json_path = File.join(Dir.tmpdir, "slo_test_#{Time.now.to_i}.json")

      begin
        Fastlane::Actions::SentrySloReportAction.run(
          auth_token: auth_token,
          org_slug: org_slug,
          project_id: project_id,
          project_slug: project_slug,
          environment: 'production',
          stats_period: '7d',
          crash_free_target: 0.998,
          ttid_p95_target_ms: 1000,
          compare_weeks: false,
          compare_releases: false,
          output_json: json_path
        )

        expect(File.exist?(json_path)).to be(true)
        written = JSON.parse(File.read(json_path))
        expect(written['period']).to eq('7d')
        expect(written['availability']).not_to be_nil
      ensure
        FileUtils.rm_f(json_path)
      end
    end
  end

  describe '#run availability only (no WoW, no RoR)' do
    before do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).and_return(sessions_response)
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_events).and_return(ttid_response)
    end

    it 'skips WoW and RoR comparisons when disabled' do
      report = Fastlane::Actions::SentrySloReportAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        project_slug: project_slug,
        environment: 'production',
        stats_period: '7d',
        crash_free_target: 0.998,
        ttid_p95_target_ms: 1000,
        compare_weeks: false,
        compare_releases: false
      )

      expect(report[:availability][:current]).not_to be_nil
      expect(report[:availability][:previous]).to be_nil
      expect(report[:availability][:delta]).to be_nil
      expect(report[:availability][:releases]).to be_nil
      expect(report[:issues]).to eq({})
    end
  end
end
