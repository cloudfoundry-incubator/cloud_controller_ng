require 'spec_helper'

RSpec.describe 'ServicePlans' do
  let(:user) { VCAP::CloudController::User.make }
  let(:space) { VCAP::CloudController::Space.make }

  before do
    space.organization.add_user(user)
    space.add_developer(user)
  end

  describe 'GET /v2/service_plans' do
    # we need a service and a plan
    let(:service) { VCAP::CloudController::Service.make }
    let!(:service_plan) { VCAP::CloudController::ServicePlan.make(
      service: service,
      maintenance_info: '{ "version":  "2.0" }')
    }

    # what is the behaviour?
    # visibile service plans are listed...

    it 'lists service plans' do
      get '/v2/service_plans', nil, headers_for(user)
      expect(last_response.status).to eq(200)

      parsed_response = MultiJson.load(last_response.body)
      expect(parsed_response).to be_a_response_like(
        {
          'total_results' => 1,
          'total_pages' => 1,
          'prev_url' => nil,
          'next_url' => nil,
          'resources' => [
            {
              'metadata' => {
                'guid' => service_plan.guid,
                'url' => "/v2/service_plans/#{service_plan.guid}",
                'created_at' => iso8601,
                'updated_at' => iso8601
              },
              'entity' => {
                'active' => true,
                'bindable' => true,
                'description' => service_plan.description,
                'extra' => nil,
                'free' => false,
                'maximum_polling_duration' => nil,
                'maintenance_info' => { 'version' => '2.0' },
                'name' => service_plan.name,
                'plan_updateable' => nil,
                'public' => true,
                'schemas' => {
                   'service_instance' => {
                      'create' => {
                         'parameters' => {}
                      },
                      'update' => {
                         'parameters' => {}
                      }
                   },
                   'service_binding' => {
                      'create' => {
                         'parameters' => {}
                      }
                   }
                },
                'service_guid' => service.guid,
                'service_instances_url' => "/v2/service_plans/#{service_plan.guid}/service_instances",
                'service_url' => "/v2/services/#{service.guid}",
                'unique_id' => service_plan.unique_id
              }
            },
          ]
        }
      )
    end

    # describe 'inline-relations-depth=1' do
    #   let(:service_binding2) { nil }
    #
    #   it 'lists service bindings and their relations' do
    #     get '/v2/service_bindings?inline-relations-depth=1', nil, headers_for(user)
    #     expect(last_response.status).to eq(200)
    #
    #     parsed_response = MultiJson.load(last_response.body)
    #     expect(parsed_response).to be_a_response_like(
    #       {
    #         'total_results' => 1,
    #         'total_pages' => 1,
    #         'prev_url' => nil,
    #         'next_url' => nil,
    #         'resources' => [
    #           {
    #             'metadata' => {
    #               'guid' => service_binding1.guid,
    #               'url' => "/v2/service_bindings/#{service_binding1.guid}",
    #               'created_at' => iso8601,
    #               'updated_at' => iso8601
    #             },
    #             'entity' => {
    #               'app_guid' => process1.guid,
    #               'service_instance_guid' => service_instance.guid,
    #               'credentials' => { 'secret' => 'key' },
    #               'name' => nil,
    #               'binding_options' => {},
    #               'gateway_data' => nil,
    #               'gateway_name' => '',
    #               'syslog_drain_url' => nil,
    #               'volume_mounts' => [],
    #               'last_operation' => {
    #                 'type' => 'create',
    #                 'state' => 'succeeded',
    #                 'description' => '',
    #                 'updated_at' => iso8601,
    #                 'created_at' => iso8601,
    #               },
    #               'app_url' => "/v2/apps/#{process1.guid}",
    #               'app' => {
    #                 'metadata' => {
    #                   'guid' => process1.guid,
    #                   'url' => "/v2/apps/#{process1.guid}",
    #                   'created_at' => iso8601,
    #                   'updated_at' => iso8601
    #                 },
    #                 'entity' => {
    #                   'name' => process1.name,
    #                   'production' => false,
    #                   'space_guid' => space.guid,
    #                   'stack_guid' => process1.stack.guid,
    #                   'buildpack' => nil,
    #                   'detected_buildpack' => nil,
    #                   'detected_buildpack_guid' => nil,
    #                   'environment_json' => nil,
    #                   'memory' => 1024,
    #                   'instances' => 1,
    #                   'disk_quota' => 1024,
    #                   'state' => 'STOPPED',
    #                   'version' => process1.version,
    #                   'command' => nil,
    #                   'console' => false,
    #                   'debug' => nil,
    #                   'staging_task_id' => process1.latest_build.guid,
    #                   'package_state' => 'STAGED',
    #                   'health_check_type' => 'port',
    #                   'health_check_timeout' => nil,
    #                   'health_check_http_endpoint' => nil,
    #                   'staging_failed_reason' => nil,
    #                   'staging_failed_description' => nil,
    #                   'diego' => true,
    #                   'docker_image' => nil,
    #                   'docker_credentials' => {
    #                     'username' => nil,
    #                     'password' => nil,
    #                   },
    #                   'package_updated_at' => iso8601,
    #                   'detected_start_command' => '',
    #                   'enable_ssh' => true,
    #                   'ports' => [8080],
    #                   'space_url' => "/v2/spaces/#{space.guid}",
    #                   'stack_url' => "/v2/stacks/#{process1.stack.guid}",
    #                   'routes_url' => "/v2/apps/#{process1.guid}/routes",
    #                   'events_url' => "/v2/apps/#{process1.guid}/events",
    #                   'service_bindings_url' => "/v2/apps/#{process1.guid}/service_bindings",
    #                   'route_mappings_url' => "/v2/apps/#{process1.guid}/route_mappings"
    #                 }
    #               },
    #               'service_binding_parameters_url' => "/v2/service_bindings/#{service_binding1.guid}/parameters",
    #               'service_instance_url' => "/v2/service_instances/#{service_instance.guid}",
    #               'service_instance' => {
    #                 'metadata' => {
    #                   'guid' => service_instance.guid,
    #                   'url' => "/v2/service_instances/#{service_instance.guid}",
    #                   'created_at' => iso8601,
    #                   'updated_at' => iso8601
    #                 },
    #                 'entity' => {
    #                   'name' => service_instance.name,
    #                   'credentials' => service_instance.credentials,
    #                   'service_plan_guid' => service_instance.service_plan.guid,
    #                   'service_guid' => service_instance.service.guid,
    #                   'space_guid' => space.guid,
    #                   'gateway_data' => nil,
    #                   'dashboard_url' => nil,
    #                   'type' => 'managed_service_instance',
    #                   'last_operation' => nil,
    #                   'tags' => [],
    #                   'space_url' => "/v2/spaces/#{space.guid}",
    #                   'service_url' => "/v2/services/#{service_instance.service.guid}",
    #                   'service_plan_url' => "/v2/service_plans/#{service_instance.service_plan.guid}",
    #                   'service_bindings_url' => "/v2/service_instances/#{service_instance.guid}/service_bindings",
    #                   'service_keys_url' => "/v2/service_instances/#{service_instance.guid}/service_keys",
    #                   'routes_url' => "/v2/service_instances/#{service_instance.guid}/routes",
    #                   'shared_from_url' => "/v2/service_instances/#{service_instance.guid}/shared_from",
    #                   'shared_to_url' => "/v2/service_instances/#{service_instance.guid}/shared_to",
    #                   'service_instance_parameters_url' => "/v2/service_instances/#{service_instance.guid}/parameters",
    #                 }
    #               }
    #             }
    #           }
    #         ]
    #       }
    #     )
    #   end
    # end
  end

  # describe 'GET /v2/service_plans/:guid' do
  #   let(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make(space: space) }
  #   let(:process1) { VCAP::CloudController::ProcessModelFactory.make(space: space) }
  #   let!(:service_binding1) do
  #     VCAP::CloudController::ServiceBinding.make(service_instance: service_instance, app: process1.app, credentials: { secret: 'key' })
  #   end
  #
  #   it 'displays the service binding' do
  #     get "/v2/service_bindings/#{service_binding1.guid}", nil, headers_for(user)
  #     expect(last_response.status).to eq(200)
  #
  #     parsed_response = MultiJson.load(last_response.body)
  #     expect(parsed_response).to be_a_response_like(
  #       {
  #         'metadata' => {
  #           'guid' => service_binding1.guid,
  #           'url' => "/v2/service_bindings/#{service_binding1.guid}",
  #           'created_at' => iso8601,
  #           'updated_at' => iso8601
  #         },
  #         'entity' => {
  #           'app_guid' => process1.guid,
  #           'service_instance_guid' => service_instance.guid,
  #           'credentials' => { 'secret' => 'key' },
  #           'name' => nil,
  #           'binding_options' => {},
  #           'gateway_data' => nil,
  #           'gateway_name' => '',
  #           'syslog_drain_url' => nil,
  #           'volume_mounts' => [],
  #           'last_operation' => {
  #             'type' => 'create',
  #             'state' => 'succeeded',
  #             'description' => '',
  #             'updated_at' => iso8601,
  #             'created_at' => iso8601,
  #           },
  #           'app_url' => "/v2/apps/#{process1.guid}",
  #           'service_instance_url' => "/v2/service_instances/#{service_instance.guid}",
  #           'service_binding_parameters_url' => "/v2/service_bindings/#{service_binding1.guid}/parameters"
  #         }
  #       }
  #     )
  #   end
  #
  #   it 'does not display service bindings without a web process' do
  #     non_web_process = VCAP::CloudController::ProcessModelFactory.make(space: space, type: 'non-web')
  #     non_displayed_binding = VCAP::CloudController::ServiceBinding.make(app: non_web_process.app, service_instance: service_instance)
  #
  #     get "/v2/service_bindings/#{non_displayed_binding.guid}", nil, headers_for(user)
  #     expect(last_response.status).to eq(404)
  #   end
  # end
end
