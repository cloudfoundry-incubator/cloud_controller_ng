require 'spec_helper'
require 'request_spec_shared_examples'
require 'models/services/service_plan'

RSpec.describe 'V3 service plan visibility' do
  let(:user) { VCAP::CloudController::User.make }
  let(:org) { VCAP::CloudController::Organization.make }
  let(:space) { VCAP::CloudController::Space.make(organization: org) }

  describe 'GET /v3/service_plans/:guid/visibility' do
    let(:api_call) { lambda { |user_headers| get "/v3/service_plans/#{guid}/visibility", {}, user_headers } }
    let(:guid) { service_plan.guid }

    context 'for public plans' do
      let!(:service_plan) { VCAP::CloudController::ServicePlan.make }
      let(:expected_codes_and_responses) {
        Hash.new(
          code: 200,
          response_object: { "type" => "public" }
        )
      }

      it_behaves_like 'permissions for single object endpoint', ALL_PERMISSIONS
    end

    context 'for admin-only plans' do
      let!(:service_plan) { VCAP::CloudController::ServicePlan.make(public: false) }
      let(:admin_only_response) {
        {
          code: 200,
          response_object: { "type" => "admin" }
        }
      }
      let(:expected_codes_and_responses) {
        Hash.new(code: 404).tap do |h|
          h['admin'] = admin_only_response
          h['admin_read_only'] = admin_only_response
          h['global_auditor'] = admin_only_response
        end
      }

      it_behaves_like 'permissions for single object endpoint', ALL_PERMISSIONS
    end

    context 'for space-scoped plans' do
      let!(:service_plan) do
        broker = VCAP::CloudController::ServiceBroker.make(space: space)
        offering = VCAP::CloudController::Service.make(service_broker: broker)
        VCAP::CloudController::ServicePlan.make(public: false, service: offering)
      end

      let(:space_response) {
        {
          code: 200,
          response_object: {
            "type" => "space",
            "space" => {
              "guid" => space.guid,
              "name" => space.name
            }
          }
        }
      }
      let(:expected_codes_and_responses) {
        Hash.new(code: 404).tap do |h|
          h['admin'] = space_response
          h['admin_read_only'] = space_response
          h['global_auditor'] = space_response
          h['space_developer'] = space_response
          h['space_manager'] = space_response
          h['space_auditor'] = space_response
        end
      }

      it_behaves_like 'permissions for single object endpoint', ALL_PERMISSIONS
    end

    context 'for org-restricted plans' do
      let(:other_org) { VCAP::CloudController::Organization.make }

      let!(:service_plan) do
        plan = VCAP::CloudController::ServicePlan.make(public: false)
        VCAP::CloudController::ServicePlanVisibility.make(service_plan: plan, organization: org)
        VCAP::CloudController::ServicePlanVisibility.make(service_plan: plan, organization: other_org)
        plan
      end

      let(:org_member_response) {
        {
          code: 200,
          response_object: {
            "type" => "organization",
            "organization" => [
              {
                "guid" => org.guid,
                "name" => org.name
              }
            ]
          }
        }
      }

      let(:admin_response) {
        {
          code: 200,
          response_object: {
            "type" => "organization",
            "organization" => [
              {
                "guid" => org.guid,
                "name" => org.name
              },
              {
                'guid' => other_org.guid,
                'name' => other_org.name
              }
            ]
          }
        }
      }

      let(:expected_codes_and_responses) {
        Hash.new(org_member_response).tap do |h|
          h['admin'] = admin_response
          h['admin_read_only'] = admin_response
          h['global_auditor'] = admin_response
          h['no_role'] = {code: 404}
        end
      }

      it_behaves_like 'permissions for single object endpoint', ALL_PERMISSIONS
    end
  end
end