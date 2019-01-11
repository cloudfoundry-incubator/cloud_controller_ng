require 'spec_helper'

RSpec.describe 'V3 migrate services' do
  describe 'migrating a service broker' do
    let!(:broker) { VCAP::CloudController::ServiceBroker.make }

    it 'is unexpectedly successful' do
      expect(VCAP::CloudController::ServiceBroker.all.length).to eq(1)

      get('/v3/external_service_brokers', {}, admin_headers)
      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(1)

      post('/v3/migrate_service_brokers', {
        broker_guid: broker.guid
      }.to_json, admin_headers)

      expect(last_response).to have_status_code(201)

      get('/v3/external_service_brokers', {}, admin_headers)
      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(2)

      expect(VCAP::CloudController::ServiceBroker.all.length).to eq(0)
    end
  end
end
