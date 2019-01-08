require 'spec_helper'

RSpec.describe 'V3 external service plans' do
  describe 'getting plans' do
    it 'has some plans' do
      get('/v3/external_service_plans', {}, admin_headers)
      expect(last_response).to have_status_code(200)

      json_body = JSON.parse(last_response.body)
      expect(json_body).to have_key('resources')
      expect(json_body['resources'].length).to eq(2)
      expect(json_body['resources'][0]['name']).to eq "complex"
    end
  end
end
