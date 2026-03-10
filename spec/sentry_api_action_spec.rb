describe Fastlane::Actions::SentryApiAction do
  describe '#run' do
    let(:auth_token) { 'test-token' }
    let(:mock_response) do
      { status: 200, body: '{"ok":true}', json: { 'ok' => true } }
    end

    before do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:api_request).and_return(mock_response)
    end

    it 'makes a generic Sentry API request and returns the result' do
      result = Fastlane::Actions::SentryApiAction.run(
        auth_token: auth_token,
        server_url: 'https://sentry.io/api/0',
        path: '/organizations/my-org/sessions/',
        params: { statsPeriod: '7d' }
      )

      expect(result[:status]).to eq(200)
      expect(result[:json]).to eq({ 'ok' => true })
    end

    it 'stores results in lane context' do
      Fastlane::Actions::SentryApiAction.run(
        auth_token: auth_token,
        server_url: 'https://sentry.io/api/0',
        path: '/organizations/my-org/sessions/',
        params: {}
      )

      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_API_STATUS_CODE]).to eq(200)
      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::SENTRY_API_JSON]).to eq({ 'ok' => true })
    end

    it 'raises an error on non-2xx status code' do
      allow(Fastlane::Helper::SentryApiHelper).to receive(:api_request).and_return(
        { status: 401, body: 'Unauthorized', json: nil }
      )

      expect do
        Fastlane::Actions::SentryApiAction.run(
          auth_token: auth_token,
          server_url: 'https://sentry.io/api/0',
          path: '/organizations/my-org/sessions/',
          params: {}
        )
      end.to raise_error(FastlaneCore::Interface::FastlaneError)
    end
  end
end
