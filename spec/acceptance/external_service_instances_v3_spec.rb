require 'spec_helper'

RSpec.describe 'V3 external service instances' do
  describe 'getting instances' do
    it 'it has some instances' do
      get('/v3/external_service_instances', {}, admin_headers)
      expect(last_response).to have_status_code(200)

      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(1)
    end
  end
end
