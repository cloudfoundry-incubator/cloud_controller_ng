require 'spec_helper'

module VCAP::CloudController
  RSpec.describe 'V3 external service bindings' do
    describe 'listing bindings' do
      it 'is wildly successful' do
        get('/v3/external_service_bindings', {}, admin_headers)
        expect(last_response).to have_status_code(200)

        json_body = JSON.parse(last_response.body)
        expect(json_body).to have_key('resources')
        expect(json_body['resources'].length).to eq(1)
        expect(json_body['resources'][0]['credentials']).to have_key('username')
        expect(json_body['resources'][0]['credentials']).to have_key('password')
      end
    end

    describe 'create a binding' do
      let(:process) { ProcessModelFactory.make }

      it 'is outrageously successful' do
        post('/v3/external_service_bindings', {
          serviceInstanceGuid: 'a90f9e2a-ef60-4de3-bceb-cd83c0bf7fc5',
          appGuid: process.app.guid
        }.to_json, admin_headers)

        expect(last_response).to have_status_code(201)

        json_body = JSON.parse(last_response.body)
        expect(json_body).to have_key('serviceInstanceGuid')
        expect(json_body['credentials']).to have_key('username')
        expect(json_body['credentials']).to have_key('password')

        expect(VCAP::CloudController::ExternalServiceBinding.first).to exist
      end
    end
  end
end
