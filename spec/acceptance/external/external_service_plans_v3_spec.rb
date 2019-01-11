require 'spec_helper'
require 'ism/client'

RSpec.describe 'V3 external service plans' do
  describe 'getting plans' do
    before do
      ism = ISM::Client.new
      ism.cleanup

      post('/v3/external_service_brokers', {
        name: 'overview-broker',
        auth_username: ENV.fetch('BESTBROKERUSERNAME'),
        auth_password: ENV.fetch('BESTBROKERPASSWORD'),
        url: 'https://the-best-broker.cfapps.io'
      }.to_json, admin_headers)
      expect(last_response).to have_status_code(201)
    end

  end

  it 'has some plans' do
    get('/v3/external_service_plans', {}, admin_headers)
    expect(last_response).to have_status_code(200)

    json_body = JSON.parse(last_response.body)
    expect(json_body).to have_key('resources')
    expect(json_body['resources'].length).to eq(1)
    expect(json_body['resources'][0]['name']).to eq 'simple'
  end
end
