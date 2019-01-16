require 'spec_helper'
require 'ism/client'

module VCAP::CloudController
  RSpec.describe 'V3 external service bindings' do
    instance_id = nil

    before do
      ism = ISM::Client.new
      ism.cleanup

      post('/v3/external_service_brokers', {
        name: 'overview-broker',
        auth_username: ENV.fetch("BESTBROKERUSERNAME"),
        auth_password: ENV.fetch("BESTBROKERPASSWORD"),
        url: ENV.fetch("BESTBROKERURL")
      }.to_json, admin_headers)
      expect(last_response).to have_status_code(201)

      get('/v3/external_services', {}, admin_headers)
      json_body = JSON.parse(last_response.body)
      serviceId = json_body['resources'][0]['guid']

      get('/v3/external_service_plans', {}, admin_headers)
      json_body = JSON.parse(last_response.body)
      planId = json_body['resources'][0]['guid']

      post('/v3/external_service_instances', {
        planId: planId,
        serviceId: serviceId,
        name: 'some-instance'
      }.to_json, admin_headers)
      expect(last_response).to have_status_code(201)
      json_body = JSON.parse(last_response.body)
      instance_id = json_body['guid']
    end

    describe 'create a binding' do
      let(:process) { ProcessModelFactory.make }

      it 'is outrageously successful' do
        post('/v3/external_service_bindings', {
          serviceInstanceGuid: instance_id,
          appGuid: process.app.guid
        }.to_json, admin_headers)

        expect(last_response).to have_status_code(201)

        json_body = JSON.parse(last_response.body)
        expect(json_body).to have_key('service_instance_guid')
        expect(json_body['credentials']).to have_key('username')
        expect(json_body['credentials']).to have_key('password')

        get('/v3/external_service_bindings', {}, admin_headers)
        expect(last_response).to have_status_code(200)

        json_body = JSON.parse(last_response.body)
        expect(json_body).to have_key('resources')
        expect(json_body['resources'].length).to eq(1)
        expect(json_body['resources'][0]['credentials']).to have_key('username')
        expect(json_body['resources'][0]['credentials']).to have_key('password')

        binding = VCAP::CloudController::ExternalServiceBinding.first
        expect(binding).to exist
        expect(binding.credentials["username"]).to eq "admin"
        expect(binding.credentials["password"]).not_to be_empty
      end
    end
  end
end
