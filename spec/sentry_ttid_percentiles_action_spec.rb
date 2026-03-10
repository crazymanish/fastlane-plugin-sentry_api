describe Fastlane::Actions::SentryTtidPercentilesAction do
  let(:auth_token) { 'test-token' }
  let(:org_slug) { 'test-org' }
  let(:project_id) { '12345' }

  let(:mock_response) do
    {
      status: 200,
      body: '{}',
      json: {
        'data' => [
          {
            'transaction' => 'MainViewController',
            'p50(measurements.time_to_initial_display)' => 320.456,
            'p75(measurements.time_to_initial_display)' => 485.123,
            'p95(measurements.time_to_initial_display)' => 890.789,
            'count()' => 125_000
          },
          {
            'transaction' => 'LotDetailViewController',
            'p50(measurements.time_to_initial_display)' => 410.2,
            'p75(measurements.time_to_initial_display)' => 620.5,
            'p95(measurements.time_to_initial_display)' => 1100.8,
            'count()' => 98_000
          }
        ]
      }
    }
  end

  describe '#run' do
    before do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_events).and_return(mock_response)
    end

    it 'returns TTID data per screen' do
      result = Fastlane::Actions::SentryTtidPercentilesAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )

      expect(result).to be_an(Array)
      expect(result.length).to eq(2)

      first = result[0]
      expect(first[:transaction]).to eq('MainViewController')
      expect(first[:p50]).to eq(320.5)
      expect(first[:p75]).to eq(485.1)
      expect(first[:p95]).to eq(890.8)
      expect(first[:count]).to eq(125_000)
    end

    it 'stores results in lane context' do
      Fastlane::Actions::SentryTtidPercentilesAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )

      ttid_data = Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_TTID_DATA]
      expect(ttid_data).to be_an(Array)
      expect(ttid_data.length).to eq(2)
    end

    it 'calls the Events API with correct params' do
      expect(Fastlane::Helper::SentryApiHelper).to receive(:get_events).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          dataset: 'metrics',
          field: [
            'transaction',
            'p50(measurements.time_to_initial_display)',
            'p75(measurements.time_to_initial_display)',
            'p95(measurements.time_to_initial_display)',
            'count()'
          ],
          project: '12345',
          query: 'event.type:transaction transaction.op:ui.load',
          sort: '-count()',
          per_page: '20',
          statsPeriod: '7d',
          environment: 'production'
        )
      ).and_return(mock_response)

      Fastlane::Actions::SentryTtidPercentilesAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        transaction_op: 'ui.load',
        per_page: 20,
        environment: 'production'
      )
    end

    it 'includes release filter in query when specified' do
      expect(Fastlane::Helper::SentryApiHelper).to receive(:get_events).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          query: 'event.type:transaction transaction.op:ui.load release:v25.10.0'
        )
      ).and_return(mock_response)

      Fastlane::Actions::SentryTtidPercentilesAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        transaction_op: 'ui.load',
        release: 'v25.10.0',
        environment: 'production'
      )
    end

    it 'supports custom date range' do
      expect(Fastlane::Helper::SentryApiHelper).to receive(:get_events).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          start: '2026-02-24T00:00:00Z',
          end: '2026-03-03T00:00:00Z'
        )
      ).and_return(mock_response)

      Fastlane::Actions::SentryTtidPercentilesAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        start_date: '2026-02-24T00:00:00Z',
        end_date: '2026-03-03T00:00:00Z',
        environment: 'production'
      )
    end
  end

  describe '#run with API error' do
    it 'raises an error on non-2xx response' do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_events).and_return(
        { status: 500, body: 'Internal Server Error', json: nil }
      )

      expect do
        Fastlane::Actions::SentryTtidPercentilesAction.run(
          auth_token: auth_token,
          org_slug: org_slug,
          project_id: project_id,
          stats_period: '7d',
          environment: 'production'
        )
      end.to raise_error(FastlaneCore::Interface::FastlaneError, /Sentry Events API error 500/)
    end
  end
end
