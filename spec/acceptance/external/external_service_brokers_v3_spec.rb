require 'spec_helper'
require 'ism/client'

RSpec.describe 'V3 service brokers' do
  describe 'getting a list of service brokers' do

    before do
      ism = ISM::Client.new
      ism.cleanup
    end

    it 'has an overview-broker broker' do
      post('/v3/external_service_brokers', {
        name: 'overview-broker',
        auth_username: ENV.fetch("BESTBROKERUSERNAME"),
        auth_password: ENV.fetch("BESTBROKERPASSWORD"),
        url: 'https://the-best-broker.cfapps.io'
      }.to_json, admin_headers)
      expect(last_response).to have_status_code(201)


      get('/v3/external_service_brokers', {}, admin_headers)
      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(1)
    end
  end
end
