require 'spec_helper'

RSpec.describe 'V3 service brokers' do
  describe 'getting a list of service brokers' do
    it 'has an overview-broker broker' do
      get('/v3/external_service_brokers', {}, admin_headers)

      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(1)
    end
  end
end
