describe Fastlane::Actions::SentryCrashFreeUsersAction do
  let(:auth_token) { 'test-token' }
  let(:org_slug) { 'test-org' }
  let(:project_id) { '12345' }

  let(:mock_response) do
    {
      status: 200,
      body: '{}',
      json: {
        'groups' => [
          {
            'by' => {},
            'totals' => {
              'crash_free_rate(user)' => 0.9991,
              'count_unique(user)' => 450_000
            }
          }
        ]
      }
    }
  end

  describe '#run' do
    before do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).and_return(mock_response)
    end

    it 'returns crash-free user rate and total users' do
      result = Fastlane::Actions::SentryCrashFreeUsersAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )

      expect(result[:crash_free_user_rate]).to eq(0.9991)
      expect(result[:total_users]).to eq(450_000)
    end

    it 'stores results in lane context' do
      Fastlane::Actions::SentryCrashFreeUsersAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )

      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_CRASH_FREE_USER_RATE_ONLY]).to eq(0.9991)
      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_TOTAL_USERS_ONLY]).to eq(450_000)
    end

    it 'queries user-centric fields only' do
      expect(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          field: ['crash_free_rate(user)', 'count_unique(user)'],
          project: '12345',
          statsPeriod: '7d',
          includeSeries: '0'
        )
      ).and_return(mock_response)

      Fastlane::Actions::SentryCrashFreeUsersAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )
    end
  end

  describe '#run with API error' do
    it 'raises an error on non-2xx response' do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_sessions).and_return(
        { status: 403, body: 'Forbidden', json: nil }
      )

      expect do
        Fastlane::Actions::SentryCrashFreeUsersAction.run(
          auth_token: auth_token,
          org_slug: org_slug,
          project_id: project_id,
          stats_period: '7d',
          environment: 'production'
        )
      end.to raise_error(FastlaneCore::Interface::FastlaneError, /Sentry Sessions API error 403/)
    end
  end
end
