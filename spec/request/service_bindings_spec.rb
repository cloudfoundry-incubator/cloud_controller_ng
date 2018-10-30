require 'spec_helper'

RSpec.describe 'v3 service bindings' do
  let(:app_model) { VCAP::CloudController::AppModel.make }
  let(:space) { app_model.space }
  let(:user) { make_developer_for_space(space) }
  let(:user_headers) { headers_for(user, user_name: user_name) }
  let(:user_name) { 'room' }

  describe 'POST /v3/service_bindings' do
    context 'managed service instance' do
      let(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make(space: space, name: 'service-instance-name') }

      before do
        allow(VCAP::Services::ServiceBrokers::V2::Client).to receive(:new) do |*args, **kwargs, &block|
          fb = FakeServiceBrokerV2Client.new(*args, **kwargs, &block)
          fb.credentials = { 'username' => 'managed_username' }
          fb.syslog_drain_url = 'syslog://mydrain.example.com'
          fb.volume_mounts = [{ 'stuff' => 'thing', 'container_dir' => 'some-path' }]
          fb
        end
      end

      it 'creates a service binding' do
        request_body = {
          type: 'app',
          data: { parameters: { potato: 'tomato' } },
          relationships: {
            app: {
              data: {
                guid: app_model.guid
              }
            },
            service_instance: {
              data: {
                guid: service_instance.guid
              }
            },
          }
        }.to_json

        post '/v3/service_bindings', request_body, user_headers

        parsed_response = MultiJson.load(last_response.body)
        guid = parsed_response['guid']

        expected_response = {
          'guid' => guid,
          'type' => 'app',
          'data' => {
            'binding_name' => nil,
            'credentials' => {
              'username' => 'managed_username'
            },
            'instance_name' => 'service-instance-name',
            'name' => 'service-instance-name',
            'syslog_drain_url' => 'syslog://mydrain.example.com',
            'volume_mounts' => [
              {
                'container_dir' => 'some-path',
              }
            ]
          },
          'created_at' => iso8601,
          'updated_at' => iso8601,
          'links' => {
            'self' => {
              'href' => "#{link_prefix}/v3/service_bindings/#{guid}"
            },
            'service_instance' => {
              'href' => "#{link_prefix}/v2/service_instances/#{service_instance.guid}"
            },
            'app' => {
              'href' => "#{link_prefix}/v3/apps/#{app_model.guid}"
            }
          }
        }

        expect(last_response).to have_status_code(201), last_response.body
        expect(parsed_response).to be_a_response_like(expected_response)
        expect(VCAP::CloudController::ServiceBinding.find(guid: guid)).to be_present

        event = VCAP::CloudController::Event.last
        expect(event.values).to match(
          hash_including({
                           type: 'audit.service_binding.create',
                           actee: guid,
                           actee_type: 'service_binding',
                           actee_name: '',
                           actor: user.guid,
                           actor_type: 'user',
                           actor_username: user_name,
                           space_guid: space.guid,
                           organization_guid: space.organization.guid
                         })
                                )
        expect(event.metadata).to eq({
                                       'request' => {
                                         'type' => 'app',
                                         'relationships' => {
                                           'app' => {
                                             'data' => {
                                               'guid' => app_model.guid,
                                             },
                                           },
                                           'service_instance' => {
                                             'data' => {
                                               'guid' => service_instance.guid,
                                             },
                                           },
                                         },
                                         'data' => '[PRIVATE DATA HIDDEN]'
                                       }
                                     })
      end
    end

    context 'user provided service instance' do
      let(:service_instance) do
        VCAP::CloudController::UserProvidedServiceInstance.make(
          space: space,
          credentials: { 'username': 'user_provided_username' },
          syslog_drain_url: 'syslog://drain.url.com',
          name: 'service-instance-name'
        )
      end

      it 'creates a service binding' do
        request_body = {
          type: 'app',
          relationships: {
            app: {
              data: { guid: app_model.guid }
            },
            service_instance: {
              data: { guid: service_instance.guid }
            },
          }
        }.to_json

        post '/v3/service_bindings', request_body, user_headers

        parsed_response = MultiJson.load(last_response.body)
        guid = parsed_response['guid']

        expected_response = {
          'guid' => guid,
          'type' => 'app',
          'data' => {
            'binding_name' => nil,
            'credentials' => {
              'username' => 'user_provided_username'
            },
            'instance_name' => 'service-instance-name',
            'name' => 'service-instance-name',
            'syslog_drain_url' => 'syslog://drain.url.com',
            'volume_mounts' => []
          },
          'created_at' => iso8601,
          'updated_at' => iso8601,
          'links' => {
            'self' => {
              'href' => "#{link_prefix}/v3/service_bindings/#{guid}"
            },
            'service_instance' => {
              'href' => "#{link_prefix}/v2/service_instances/#{service_instance.guid}"
            },
            'app' => {
              'href' => "#{link_prefix}/v3/apps/#{app_model.guid}"
            }
          }
        }

        parsed_response = MultiJson.load(last_response.body)

        expect(last_response).to have_status_code(201)
        expect(parsed_response).to be_a_response_like(expected_response)
        expect(VCAP::CloudController::ServiceBinding.find(guid: guid)).to be_present
      end
    end
  end

  describe 'DELETE /v3/service_bindings/:guid' do
    let(:service_binding) { VCAP::CloudController::ServiceBinding.make(service_instance: service_instance) }

    context 'managed service instance' do
      let(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make(space: space) }

      before do
        allow(VCAP::Services::ServiceBrokers::V2::Client).to receive(:new) do |*args, **kwargs, &block|
          FakeServiceBrokerV2Client.new(*args, **kwargs, &block)
        end
      end

      it 'deletes the service binding and returns a 204' do
        delete "/v3/service_bindings/#{service_binding.guid}", nil, user_headers

        expect(last_response).to have_status_code(204)
        expect(service_binding.exists?).to be_falsey

        event = VCAP::CloudController::Event.last
        expect(event.type).to eq('audit.service_binding.delete')
        expect(event.actee).to eq(service_binding.guid)
        expect(event.actee_type).to eq('service_binding')
        expect(event.actee_name).to eq('')
        expect(event.actor).to eq(user.guid)
        expect(event.actor_type).to eq('user')
        expect(event.actor_username).to eq(user_name)
        expect(event.space_guid).to eq(space.guid)
        expect(event.organization_guid).to eq(space.organization.guid)
        expect(event.metadata).to eq(
          'request' => {
            'app_guid' => service_binding.app_guid,
            'service_instance_guid' => service_binding.service_instance_guid,
          }
        )
      end
    end

    context 'user provided service instance' do
      let(:service_instance) { VCAP::CloudController::UserProvidedServiceInstance.make(space: space) }

      it 'deletes the service binding and returns a 204' do
        delete "/v3/service_bindings/#{service_binding.guid}", nil, user_headers

        expect(last_response).to have_status_code(204)
        expect(service_binding.exists?).to be_falsey

        event = VCAP::CloudController::Event.last
        expect(event.type).to eq('audit.service_binding.delete')
        expect(event.actee).to eq(service_binding.guid)
        expect(event.actee_type).to eq('service_binding')
        expect(event.actee_name).to eq('')
        expect(event.actor).to eq(user.guid)
        expect(event.actor_type).to eq('user')
        expect(event.actor_username).to eq(user_name)
        expect(event.space_guid).to eq(space.guid)
        expect(event.organization_guid).to eq(space.organization.guid)
        expect(event.metadata).to eq(
          'request' => {
            'app_guid' => service_binding.app_guid,
            'service_instance_guid' => service_binding.service_instance_guid,
          }
        )
      end
    end
  end

  describe 'GET /v3/service_bindings/:guid' do
    let(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make(space: space, name: 'service-instance-name') }
    let(:service_binding) do
      VCAP::CloudController::ServiceBinding.make(
        service_instance: service_instance,
        app: app_model,
        credentials: { 'username' => 'managed_username' },
        name: 'binding-name',
        syslog_drain_url: 'syslog://mydrain.example.com',
        volume_mounts: [{ 'stuff' => 'thing', 'container_dir' => 'some-path' }],
      )
    end

    it 'returns a service_binding' do
      get "/v3/service_bindings/#{service_binding.guid}", nil, user_headers

      parsed_response = MultiJson.load(last_response.body)

      expected_response = {
        'guid' => service_binding.guid,
        'type' => 'app',
        'data' => {
          'binding_name' => 'binding-name',
          'credentials' => {
            'username' => 'managed_username'
          },
          'instance_name' => 'service-instance-name',
          'name' => 'binding-name',
          'syslog_drain_url' => 'syslog://mydrain.example.com',
          'volume_mounts' => [{ 'container_dir' => 'some-path' }]
        },
        'created_at' => iso8601,
        'updated_at' => iso8601,
        'links' => {
          'self' => {
            'href' => "#{link_prefix}/v3/service_bindings/#{service_binding.guid}"
          },
          'service_instance' => {
            'href' => "#{link_prefix}/v2/service_instances/#{service_instance.guid}"
          },
          'app' => {
            'href' => "#{link_prefix}/v3/apps/#{app_model.guid}"
          }
        }
      }

      expect(last_response).to have_status_code(200)
      expect(parsed_response).to be_a_response_like(expected_response)
    end

    it 'redacts credentials for space auditors' do
      auditor = VCAP::CloudController::User.make
      space.organization.add_user(auditor)
      space.add_auditor(auditor)

      get "/v3/service_bindings/#{service_binding.guid}", nil, headers_for(auditor)

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response).to have_status_code(200)
      expect(parsed_response['data']['credentials']).to eq({ 'redacted_message' => '[PRIVATE DATA HIDDEN]' })
    end
  end

  describe 'GET /v3/service_bindings' do
    let(:service_instance1) { VCAP::CloudController::ManagedServiceInstance.make(space: space, name: 'service-instance-1') }
    let(:service_instance2) { VCAP::CloudController::ManagedServiceInstance.make(space: space, name: 'service-instance-2') }
    let(:service_instance3) { VCAP::CloudController::ManagedServiceInstance.make(space: space, name: 'service-instance-3') }
    let!(:service_binding1) do
      VCAP::CloudController::ServiceBinding.make(
        service_instance: service_instance1,
        app: app_model,
        credentials: { 'binding1' => 'shtuff' },
        syslog_drain_url: 'syslog://binding1.example.com',
        volume_mounts: [{ 'stuff' => 'thing', 'container_dir' => 'some-path' }],
      )
    end
    let!(:service_binding2) do
      VCAP::CloudController::ServiceBinding.make(
        service_instance: service_instance2,
        app: app_model,
        credentials: { 'binding2' => 'things' },
        syslog_drain_url: 'syslog://binding2.example.com',
        volume_mounts: [{ 'stuff2' => 'thing2', 'container_dir' => 'some-path' }],
      )
    end

    before { VCAP::CloudController::ServiceBinding.make(service_instance: service_instance3, app: app_model) }

    it 'returns a paginated list of service_bindings' do
      get '/v3/service_bindings?per_page=2', nil, user_headers

      expected_response = {
        'pagination' => {
          'total_results' => 3,
          'total_pages' => 2,
          'first' => { 'href' => "#{link_prefix}/v3/service_bindings?page=1&per_page=2" },
          'last' => { 'href' => "#{link_prefix}/v3/service_bindings?page=2&per_page=2" },
          'next' => { 'href' => "#{link_prefix}/v3/service_bindings?page=2&per_page=2" },
          'previous' => nil,
        },
        'resources' => [
          {
            'guid' => service_binding1.guid,
            'type' => 'app',
            'data' => {
              'binding_name' => nil,
              'instance_name' => 'service-instance-1',
              'name' => 'service-instance-1',
              'credentials' => {
                'redacted_message' => '[PRIVATE DATA HIDDEN IN LISTS]'
              },
              'syslog_drain_url' => 'syslog://binding1.example.com',
              'volume_mounts' => [{ 'container_dir' => 'some-path' }]
            },
            'created_at' => iso8601,
            'updated_at' => iso8601,
            'links' => {
              'self' => {
                'href' => "#{link_prefix}/v3/service_bindings/#{service_binding1.guid}"
              },
              'service_instance' => {
                'href' => "#{link_prefix}/v2/service_instances/#{service_instance1.guid}"
              },
              'app' => {
                'href' => "#{link_prefix}/v3/apps/#{app_model.guid}"
              }
            }
          },
          {
            'guid' => service_binding2.guid,
            'type' => 'app',
            'data' => {
              'binding_name' => nil,
              'instance_name' => 'service-instance-2',
              'name' => 'service-instance-2',
              'credentials' => {
                'redacted_message' => '[PRIVATE DATA HIDDEN IN LISTS]'
              },
              'syslog_drain_url' => 'syslog://binding2.example.com',
              'volume_mounts' => [{ 'container_dir' => 'some-path' }]
            },
            'created_at' => iso8601,
            'updated_at' => iso8601,
            'links' => {
              'self' => {
                'href' => "#{link_prefix}/v3/service_bindings/#{service_binding2.guid}"
              },
              'service_instance' => {
                'href' => "#{link_prefix}/v2/service_instances/#{service_instance2.guid}"
              },
              'app' => {
                'href' => "#{link_prefix}/v3/apps/#{app_model.guid}"
              }
            }
          }
        ]
      }

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response).to have_status_code(200)
      expect(parsed_response).to be_a_response_like(expected_response)
    end

    context 'faceted list' do
      context 'by app_guids' do
        let(:app_model2) { VCAP::CloudController::AppModel.make(space: space) }
        let!(:another_apps_service_binding) do
          VCAP::CloudController::ServiceBinding.make(service_instance: service_instance1,
                                                     app: app_model2,
                                                     credentials: { 'utako' => 'secret' },
                                                     syslog_drain_url: 'syslog://example.com',
                                                     volume_mounts: [{ 'stuff' => 'thing', 'container_dir' => 'some-path' }],
          )
        end
        let(:app_model3) { VCAP::CloudController::AppModel.make(space: space) }
        let!(:another_apps_service_binding2) do
          VCAP::CloudController::ServiceBinding.make(service_instance: service_instance1,
                                                     app: app_model3,
                                                     credentials: { 'amelia' => 'apples' },
                                                     syslog_drain_url: 'www.neopets.com',
                                                     volume_mounts: [{ 'stuff2' => 'thing2', 'container_dir' => 'some-path' }],
          )
        end

        it 'returns only the matching service bindings' do
          get "/v3/service_bindings?per_page=2&app_guids=#{app_model2.guid},#{app_model3.guid}", nil, user_headers

          parsed_response = MultiJson.load(last_response.body)

          expect(last_response).to have_status_code(200)
          expect(parsed_response['resources'].map { |r| r['guid'] }).to eq([another_apps_service_binding.guid, another_apps_service_binding2.guid])
          expect(parsed_response['pagination']).to be_a_response_like(
            {
              'total_results' => 2,
              'total_pages' => 1,
              'first' => { 'href' => "#{link_prefix}/v3/service_bindings?app_guids=#{app_model2.guid}%2C#{app_model3.guid}&page=1&per_page=2" },
              'last' => { 'href' => "#{link_prefix}/v3/service_bindings?app_guids=#{app_model2.guid}%2C#{app_model3.guid}&page=1&per_page=2" },
              'next' => nil,
              'previous' => nil,
            }
                                                   )
        end
      end

      context 'by service instance guids' do
        it 'returns only the matching service bindings' do
          get "/v3/service_bindings?per_page=2&service_instance_guids=#{service_instance1.guid},#{service_instance2.guid}", nil, user_headers

          parsed_response = MultiJson.load(last_response.body)

          expect(last_response).to have_status_code(200)
          expect(parsed_response['resources'].map { |r| r['guid'] }).to eq([service_binding1.guid, service_binding2.guid])
          expect(parsed_response['pagination']).to be_a_response_like(
            {
              'total_results' => 2,
              'total_pages' => 1,
              'first' => { 'href' => "#{link_prefix}/v3/service_bindings?page=1&per_page=2&service_instance_guids=#{service_instance1.guid}%2C#{service_instance2.guid}" },
              'last' => { 'href' => "#{link_prefix}/v3/service_bindings?page=1&per_page=2&service_instance_guids=#{service_instance1.guid}%2C#{service_instance2.guid}" },
              'next' => nil,
              'previous' => nil,
            }
                                                   )
        end
      end
    end
  end
end
