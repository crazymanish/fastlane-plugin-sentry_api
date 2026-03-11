describe Fastlane::Actions::SentryAppLaunchAction do
  let(:auth_token) { 'test-token' }
  let(:org_slug) { 'test-org' }
  let(:project_id) { '12345' }

  let(:cold_start_response) do
    {
      status: 200,
      body: '{}',
      json: {
        'data' => [
          {
            'p50(measurements.app_start_cold)' => 1522.3,
            'p75(measurements.app_start_cold)' => 2800.5,
            'p95(measurements.app_start_cold)' => 4916.1,
            'count()' => 85_000
          }
        ]
      }
    }
  end

  let(:warm_start_response) do
    {
      status: 200,
      body: '{}',
      json: {
        'data' => [
          {
            'p50(measurements.app_start_warm)' => 280.4,
            'p75(measurements.app_start_warm)' => 420.7,
            'p95(measurements.app_start_warm)' => 890.2,
            'count()' => 120_000
          }
        ]
      }
    }
  end

  describe '#run' do
    before do
      call_count = 0
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_events) do |**args|
        call_count += 1
        query = args[:params][:query]
        if query.include?('app_start_cold')
          cold_start_response
        else
          warm_start_response
        end
      end
    end

    it 'returns cold and warm start data' do
      result = Fastlane::Actions::SentryAppLaunchAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )

      expect(result).to be_a(Hash)

      cold = result[:cold_start]
      expect(cold[:p50]).to eq(1522.3)
      expect(cold[:p75]).to eq(2800.5)
      expect(cold[:p95]).to eq(4916.1)
      expect(cold[:count]).to eq(85_000)

      warm = result[:warm_start]
      expect(warm[:p50]).to eq(280.4)
      expect(warm[:p75]).to eq(420.7)
      expect(warm[:p95]).to eq(890.2)
      expect(warm[:count]).to eq(120_000)
    end

    it 'stores results in lane context' do
      Fastlane::Actions::SentryAppLaunchAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )

      data = Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_APP_LAUNCH_DATA]
      expect(data).to be_a(Hash)
      expect(data[:cold_start]).not_to be_nil
      expect(data[:warm_start]).not_to be_nil
    end

    it 'calls the Events API with correct params for cold start' do
      expect(Fastlane::Helper::SentryApiHelper).to receive(:get_events).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          dataset: 'metrics',
          field: [
            'p50(measurements.app_start_cold)',
            'p75(measurements.app_start_cold)',
            'p95(measurements.app_start_cold)',
            'count()'
          ],
          project: '12345',
          query: 'event.type:transaction has:measurements.app_start_cold',
          per_page: '1',
          statsPeriod: '7d',
          environment: 'production'
        )
      ).and_return(cold_start_response)

      # Allow the warm start call too
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_events).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          query: 'event.type:transaction has:measurements.app_start_warm'
        )
      ).and_return(warm_start_response)

      Fastlane::Actions::SentryAppLaunchAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )
    end

    it 'includes release filter in query when specified' do
      expect(Fastlane::Helper::SentryApiHelper).to receive(:get_events).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          query: 'event.type:transaction has:measurements.app_start_cold release:v25.10.0'
        )
      ).and_return(cold_start_response)

      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_events).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          query: 'event.type:transaction has:measurements.app_start_warm release:v25.10.0'
        )
      ).and_return(warm_start_response)

      Fastlane::Actions::SentryAppLaunchAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
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
      ).and_return(cold_start_response)

      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_events).with(
        auth_token: auth_token,
        org_slug: org_slug,
        params: hash_including(
          start: '2026-02-24T00:00:00Z',
          end: '2026-03-03T00:00:00Z'
        )
      ).and_return(warm_start_response)

      Fastlane::Actions::SentryAppLaunchAction.run(
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
    it 'raises an error on non-2xx cold start response' do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_events).and_return(
        { status: 500, body: 'Internal Server Error', json: nil }
      )

      expect do
        Fastlane::Actions::SentryAppLaunchAction.run(
          auth_token: auth_token,
          org_slug: org_slug,
          project_id: project_id,
          stats_period: '7d',
          environment: 'production'
        )
      end.to raise_error(FastlaneCore::Interface::FastlaneError, /Sentry Events API error 500/)
    end
  end

  describe '#run with empty data' do
    before do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_events).and_return(
        { status: 200, body: '{}', json: { 'data' => [] } }
      )
    end

    it 'returns nil values when no data is available' do
      result = Fastlane::Actions::SentryAppLaunchAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_id: project_id,
        stats_period: '7d',
        environment: 'production'
      )

      expect(result[:cold_start][:p50]).to be_nil
      expect(result[:cold_start][:p95]).to be_nil
      expect(result[:warm_start][:p50]).to be_nil
      expect(result[:warm_start][:p95]).to be_nil
    end
  end
end
