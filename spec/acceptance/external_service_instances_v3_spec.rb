require 'spec_helper'

RSpec.describe 'V3 external service instances' do
  describe 'creating instances' do
    it 'is wildly successful' do
      post('/v3/external_service_instances', {
        plan: '5ce5a482ff64a53cc1670994d60b9003',
        service: '33ceba5779bfa320a1ef0694d98069df',
        name: 'some-instance'
      }.to_json, admin_headers)
      expect(last_response).to have_status_code(201)
      json_body = JSON.parse(last_response.body)
      expect(json_body['spec']['name']).to eq('some-instance')

      get('/v3/external_service_instances', {}, admin_headers)
      expect(last_response).to have_status_code(200)

      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(1)
      expect(json_body['resources'][0]['name']).to eq('some-instance')
    end
  end
end
