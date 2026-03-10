describe Fastlane::Actions::SentryCrashFreeSessionsAction do
  let(:auth_token) { 'test-token' }
  let(:org_slug) { 'test-org' }
  let(:project_id) { '12345' }

  let(:aggregate_response) do
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

  let(:grouped_response) do
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
              'sum(session)' => 500_000,
              'count_unique(user)' => 200_000
            }
          },
          {
            'by' => { 'release' => 'v25.9.0' },
            'totals' => {
              'crash_free_rate(session)' => 0.9972,
              'crash_free_rate(user)' => 0.9985,
              'sum(session)' => 750_000,
              'count_unique(user)' => 250_000
            }
          }
        ]
      }
    }
  end

  describe '#run with aggregate metrics' do
    before do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).and_return(aggregate_response)
    end

    it 'returns crash-free session and user rates' do
      result = Fastlane::Actions::SentryCrashFreeSessionsAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )

      expect(result[:crash_free_session_rate]).to eq(0.9974)
      expect(result[:crash_free_user_rate]).to eq(0.9981)
      expect(result[:total_sessions]).to eq(1_250_000)
      expect(result[:total_users]).to eq(450_000)
      expect(result[:groups]).to be_nil
    end

    it 'stores results in lane context' do
      Fastlane::Actions::SentryCrashFreeSessionsAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )

      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_CRASH_FREE_SESSION_RATE]).to eq(0.9974)
      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_CRASH_FREE_USER_RATE]).to eq(0.9981)
      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_TOTAL_SESSIONS]).to eq(1_250_000)
      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_TOTAL_USERS]).to eq(450_000)
    end

    it 'calls the Sessions API with correct params' do
      expect(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          field: ['crash_free_rate(session)', 'crash_free_rate(user)', 'sum(session)', 'count_unique(user)'],
          project: '12345',
          statsPeriod: '7d',
          environment: 'production',
          includeSeries: '0'
        )
      ).and_return(aggregate_response)

      Fastlane::Actions::SentryCrashFreeSessionsAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )
    end
  end

  describe '#run with start_date/end_date' do
    before do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).and_return(aggregate_response)
    end

    it 'uses start/end instead of statsPeriod' do
      expect(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          start: '2026-02-24T00:00:00Z',
          end: '2026-03-03T00:00:00Z'
        )
      ).and_return(aggregate_response)

      Fastlane::Actions::SentryCrashFreeSessionsAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        start_date: '2026-02-24T00:00:00Z',
        end_date: '2026-03-03T00:00:00Z',
        environment: 'production'
      )
    end
  end

  describe '#run with group_by release' do
    before do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).and_return(grouped_response)
    end

    it 'returns grouped results by release' do
      result = Fastlane::Actions::SentryCrashFreeSessionsAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '30d',
        group_by: 'release',
        per_page: 5,
        environment: 'production'
      )

      expect(result[:groups]).to be_an(Array)
      expect(result[:groups].length).to eq(2)
      expect(result[:groups][0][:by]).to eq({ 'release' => 'v25.10.0' })
      expect(result[:groups][0][:crash_free_session_rate]).to eq(0.9981)
      expect(result[:groups][1][:by]).to eq({ 'release' => 'v25.9.0' })
      expect(result[:groups][1][:crash_free_session_rate]).to eq(0.9972)
    end

    it 'includes groupBy in API params' do
      expect(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          groupBy: 'release',
          per_page: '5',
          orderBy: '-sum(session)'
        )
      ).and_return(grouped_response)

      Fastlane::Actions::SentryCrashFreeSessionsAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '30d',
        group_by: 'release',
        per_page: 5,
        order_by: '-sum(session)',
        environment: 'production'
      )
    end
  end

  describe '#run with API error' do
    before do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).and_return(
        { status: 401, body: 'Unauthorized', json: nil }
      )
    end

    it 'raises an error on non-2xx response' do
      expect do
        Fastlane::Actions::SentryCrashFreeSessionsAction.run(
          auth_token: auth_token,
          org_slug: org_slug,
          project_id: project_id,
          stats_period: '7d',
          environment: 'production'
        )
      end.to raise_error(FastlaneCore::Interface::FastlaneError, /Sentry Sessions API error 401/)
    end
  end
end
