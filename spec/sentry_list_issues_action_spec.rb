describe Fastlane::Actions::SentryListIssuesAction do
  let(:auth_token) { 'test-token' }
  let(:org_slug) { 'test-org' }
  let(:project_slug) { 'ios' }

  let(:mock_response) do
    {
      status: 200,
      body: '[]',
      json: [
        {
          'id' => '111',
          'shortId' => 'MBA-1234',
          'title' => 'NSInternalInconsistencyException',
          'culprit' => 'MainViewController.viewDidLoad',
          'level' => 'error',
          'status' => 'unresolved',
          'count' => '450',
          'userCount' => 120,
          'firstSeen' => '2026-03-05T10:00:00Z',
          'lastSeen' => '2026-03-10T08:00:00Z',
          'permalink' => 'https://sentry.io/issues/111/',
          'metadata' => { 'type' => 'NSInternalInconsistencyException' }
        },
        {
          'id' => '222',
          'shortId' => 'MBA-1235',
          'title' => 'EXC_BAD_ACCESS in ImageLoader',
          'culprit' => 'ImageLoader.loadImage',
          'level' => 'fatal',
          'status' => 'unresolved',
          'count' => '230',
          'userCount' => 85,
          'firstSeen' => '2026-03-06T14:00:00Z',
          'lastSeen' => '2026-03-09T22:00:00Z',
          'permalink' => 'https://sentry.io/issues/222/',
          'metadata' => { 'type' => 'EXC_BAD_ACCESS' }
        }
      ]
    }
  end

  describe '#run' do
    before do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_issues).and_return(mock_response)
    end

    it 'returns parsed issues' do
      result = Fastlane::Actions::SentryListIssuesAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_slug: project_slug,
        query: 'is:unresolved',
        sort: 'freq'
      )

      expect(result[:count]).to eq(2)
      expect(result[:issues]).to be_an(Array)

      first = result[:issues][0]
      expect(first[:short_id]).to eq('MBA-1234')
      expect(first[:title]).to eq('NSInternalInconsistencyException')
      expect(first[:event_count]).to eq(450)
      expect(first[:user_count]).to eq(120)
      expect(first[:level]).to eq('error')
    end

    it 'stores results in lane context' do
      Fastlane::Actions::SentryListIssuesAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_slug: project_slug,
        query: 'is:unresolved',
        sort: 'freq'
      )

      issues = Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_ISSUES]
      expect(issues.length).to eq(2)
      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_ISSUE_COUNT]).to eq(2)
    end

    it 'calls Issues API with correct params' do
      expect(Fastlane::Helper::SentryApiHelper).to receive(:get_issues).with(
        auth_token: auth_token,
        org_slug: org_slug,
        project_slug: project_slug,
        params: hash_including(
          query: 'is:unresolved release:v25.10.0',
          sort: 'freq',
          per_page: '10'
        )
      ).and_return(mock_response)

      Fastlane::Actions::SentryListIssuesAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_slug: project_slug,
        query: 'is:unresolved release:v25.10.0',
        sort: 'freq',
        per_page: 10
      )
    end
  end

  describe '#run with empty results' do
    it 'returns empty array when no issues found' do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_issues).and_return(
        { status: 200, body: '[]', json: [] }
      )

      result = Fastlane::Actions::SentryListIssuesAction.run(
        auth_token: auth_token,
        org_slug: org_slug,
        project_slug: project_slug,
        query: 'is:unresolved',
        sort: 'freq'
      )

      expect(result[:count]).to eq(0)
      expect(result[:issues]).to eq([])
    end
  end

  describe '#run with API error' do
    it 'raises an error on non-2xx response' do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:get_issues).and_return(
        { status: 404, body: 'Not Found', json: nil }
      )

      expect do
        Fastlane::Actions::SentryListIssuesAction.run(
          auth_token: auth_token,
          org_slug: org_slug,
          project_slug: project_slug,
          query: 'is:unresolved',
          sort: 'freq'
        )
      end.to raise_error(FastlaneCore::Interface::FastlaneError, /Sentry Issues API error 404/)
    end
  end
end
