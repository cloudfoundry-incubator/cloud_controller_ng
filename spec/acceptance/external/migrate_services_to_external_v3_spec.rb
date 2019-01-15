require 'spec_helper'
require 'ism/client'

RSpec.describe 'V3 migrate services' do
  describe 'migrating a service broker' do
    let!(:broker) { VCAP::CloudController::ServiceBroker.make(broker_url: ENV.fetch('BESTBROKERURL'), auth_username: ENV.fetch('BESTBROKERUSERNAME') , auth_password: ENV.fetch('BESTBROKERPASSWORD')) }
    let!(:service) { VCAP::CloudController::Service.make(service_broker: broker, unique_id: '33ceba5779bfa320a1ef0694d98069df') }
    let!(:service_plan) { VCAP::CloudController::ServicePlan.make(service: service, unique_id: '5ce5a482ff64a53cc1670994d60b9003') }
    let!(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make(service_plan: service_plan) }
    let!(:service_binding) { VCAP::CloudController::ServiceBinding.make(service_instance: service_instance) }

    before do
      ism = ISM::Client.new
      ism.cleanup
    end

    it 'is unexpectedly successful' do
      expect(VCAP::CloudController::ServiceBroker.all.length).to eq(1)
      expect(VCAP::CloudController::ManagedServiceInstance.all.length).to eq(1)
      expect(VCAP::CloudController::ServiceBinding.all.length).to eq(1)

      get('/v3/external_service_brokers', {}, admin_headers)
      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(0)

      get('/v3/external_services', {}, admin_headers)
      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(0)

      get('/v3/external_service_instances', {}, admin_headers)
      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(0)

      post('/v3/migrate_service_brokers', {
        broker_guid: broker.guid
      }.to_json, admin_headers)

      expect(last_response).to have_status_code(201)

      get('/v3/external_service_brokers', {}, admin_headers)
      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(1)

      get('/v3/external_services', {}, admin_headers)
      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(1)

      get('/v3/external_service_instances', {}, admin_headers)
      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(1)

      expect(VCAP::CloudController::ServiceBroker.all.length).to eq(0)
      expect(VCAP::CloudController::ManagedServiceInstance.all.length).to eq(0)
      expect(VCAP::CloudController::ServiceBinding.all.length).to eq(0)
    end
  end
end
