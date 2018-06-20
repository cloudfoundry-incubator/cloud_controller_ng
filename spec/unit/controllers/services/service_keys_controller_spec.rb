require 'spec_helper'

module VCAP::CloudController
  RSpec.describe ServiceKeysController do
    describe 'Attributes' do
      it do
        expect(ServiceKeysController).to have_creatable_attributes({
           name: { type: 'string', required: true },
           service_instance_guid: { type: 'string', required: true },
           parameters: { type: 'hash', required: false }
         })
      end
    end

    let(:credentials) { { 'foo' => 'bar' } }

    let(:guid_pattern) { '[[:alnum:]-]+' }
    let(:bind_status) { 200 }
    let(:bind_body) { { credentials: credentials } }
    let(:unbind_status) { 200 }
    let(:unbind_body) { {} }

    def broker_url(broker)
      broker.broker_url
    end

    def stub_requests(broker)
      stub_request(:put, %r{#{broker_url(broker)}/v2/service_instances/#{guid_pattern}/service_bindings/#{guid_pattern}}).
        with(basic_auth: basic_auth(service_broker: broker)).
        to_return(status: bind_status, body: bind_body.to_json)
      stub_request(:delete, %r{#{broker_url(broker)}/v2/service_instances/#{guid_pattern}/service_bindings/#{guid_pattern}}).
        with(basic_auth: basic_auth(service_broker: broker)).
        to_return(status: unbind_status, body: unbind_body.to_json)
    end

    def bind_url_regex(opts={})
      service_binding = opts[:service_binding]
      service_binding_guid = service_binding.try(:guid) || guid_pattern
      service_instance = opts[:service_instance] || service_binding.try(:service_instance)
      service_instance_guid = service_instance.try(:guid) || guid_pattern
      broker = opts[:service_broker] || service_instance.service_plan.service.service_broker
      %r{#{broker_url(broker)}/v2/service_instances/#{service_instance_guid}/service_bindings/#{service_binding_guid}}
    end

    describe 'Dependencies' do
      let(:object_renderer) { double :object_renderer }
      let(:collection_renderer) { double :collection_renderer }
      let(:dependencies) { {
          object_renderer: object_renderer,
          collection_renderer: collection_renderer,
          statsd_client: double(Statsd),
          perm_client: double(Perm::Client)
      }}
      let(:config) { double(Config, get: nil) }
      let(:logger) { Steno.logger('vcap_spec') }

      it 'contains services_event_repository in the dependencies' do
        expect(ServiceKeysController.dependencies).to include :services_event_repository
      end

      it 'injects the services_event_repository dependency' do
        expect { ServiceKeysController.new(config, logger, {}, {}, nil, nil, dependencies) }.to raise_error KeyError, 'key not found: :services_event_repository'
      end
    end

    describe 'Permissions' do
      include_context 'permissions'

      before do
        @service_instance_a = ManagedServiceInstance.make(space: @space_a)
        @obj_a = ServiceKey.make(
          name: 'fake-name-a',
          service_instance: @service_instance_a
        )

        @service_instance_b = ManagedServiceInstance.make(space: @space_b)
        @obj_b = ServiceKey.make(
          name: 'fake-name-b',
          service_instance: @service_instance_b
        )
      end

      describe 'Org Level Permissions' do
        describe 'OrgManager' do
          let(:member_a) { @org_a_manager }
          let(:member_b) { @org_b_manager }

          include_examples 'permission enumeration', 'OrgManager',
                           name: 'getting service key',
                           path: '/v2/service_keys',
                           enumerate: 0
        end

        describe 'OrgUser' do
          let(:member_a) { @org_a_member }
          let(:member_b) { @org_b_member }

          include_examples 'permission enumeration', 'OrgUser',
                           name: 'getting service key',
                           path: '/v2/service_keys',
                           enumerate: 0
        end

        describe 'BillingManager' do
          let(:member_a) { @org_a_billing_manager }
          let(:member_b) { @org_b_billing_manager }

          include_examples 'permission enumeration', 'BillingManager',
                           name: 'getting service key',
                           path: '/v2/service_keys',
                           enumerate: 0
        end

        describe 'Auditor' do
          let(:member_a) { @org_a_auditor }
          let(:member_b) { @org_b_auditor }

          include_examples 'permission enumeration', 'Auditor',
                           name: 'getting service key',
                           path: '/v2/service_keys',
                           enumerate: 0
        end
      end

      describe 'App Space Level Permissions' do
        describe 'SpaceManager' do
          let(:member_a) { @space_a_manager }
          let(:member_b) { @space_b_manager }

          include_examples 'permission enumeration', 'SpaceManager',
                           name: 'getting service key',
                           path: '/v2/service_keys',
                           enumerate: 0
        end

        describe 'Developer' do
          let(:member_a) { @space_a_developer }
          let(:member_b) { @space_b_developer }

          include_examples 'permission enumeration', 'Developer',
                           name: 'getting service key',
                           path: '/v2/service_keys',
                           enumerate: 1
        end

        describe 'SpaceAuditor' do
          let(:member_a) { @space_a_auditor }
          let(:member_b) { @space_b_auditor }

          include_examples 'permission enumeration', 'SpaceAuditor',
                           name: 'getting service key',
                           path: '/v2/service_keys',
                           enumerate: 0
        end
      end
    end

    describe 'create' do
      let(:broker) { ServiceBroker.make }
      let(:service) { Service.make(bindings_retrievable: false, service_broker: broker) }
      let(:service_plan) { ServicePlan.make(service: service) }
      let(:instance) { ManagedServiceInstance.make(service_plan: service_plan) }

      let(:space) { instance.space }
      let(:developer) { make_developer_for_space(space) }
      let(:name) { 'fake-service-key' }
      let(:service_instance_guid) { instance.guid }
      let(:req) do
        {
          name: name,
          service_instance_guid: service_instance_guid
        }.to_json
      end

      before { set_current_user(developer, email: 'email@example.com') }

      context 'for managed services' do
        before do
          stub_requests(service.service_broker)
        end

        it 'creates a service key to a service instance' do
          post '/v2/service_keys', req
          expect(last_response).to have_status_code(201)
          service_key = ServiceKey.last
          expect(service_key.credentials).to eq(credentials)
        end

        it 'makes a bind request with the correct message' do
          post '/v2/service_keys', req
          expect(last_response).to have_status_code 201

          url_regex = %r{#{broker_url(service.service_broker)}/v2/service_instances/#{guid_pattern}/service_bindings/#{guid_pattern}}
          expected_body = {
            service_id: service.broker_provided_id,
            plan_id: instance.service_plan.broker_provided_id,
            bind_resource: { credential_client_id: TestConfig.config_instance.get(:cc_service_key_client_name) },
            context: {
              platform: 'cloudfoundry',
              organization_guid: instance.organization.guid,
              space_guid: instance.space.guid
            }
          }.to_json

          expect(a_request(:put, url_regex).with(body: expected_body)).to have_been_made
        end

        it 'creates an audit event after a service key created' do
          req = {
              name: 'fake-service-key',
              service_instance_guid: instance.guid
          }

          post '/v2/service_keys', req.to_json

          service_key = ServiceKey.last

          event = Event.first(type: 'audit.service_key.create')
          expect(event.actor_type).to eq('user')
          expect(event.timestamp).to be
          expect(event.actor).to eq(developer.guid)
          expect(event.actor_name).to eq('email@example.com')
          expect(event.actee).to eq(service_key.guid)
          expect(event.actee_type).to eq('service_key')
          expect(event.actee_name).to eq('fake-service-key')
          expect(event.space_guid).to eq(space.guid)
          expect(event.organization_guid).to eq(space.organization.guid)

          expect(event.metadata).to include({
                                                'request' => {
                                                    'service_instance_guid' => req[:service_instance_guid],
                                                    'name' => req[:name]
                                                }
                                            })
        end

        context 'when attempting to create service key for an unbindable service' do
          before do
            service.bindable = false
            service.save

            req = {
                name: name,
                service_instance_guid: instance.guid }.to_json

            post '/v2/service_keys', req
          end

          it 'raises ServiceKeyNotSupported error' do
            hash_body = JSON.parse(last_response.body)
            expect(hash_body['error_code']).to eq('CF-ServiceKeyNotSupported')
            expect(last_response).to have_status_code(400)
          end

          it 'does not send a bind request to broker' do
            expect(a_request(:put, bind_url_regex(service_instance: instance))).to_not have_been_made
          end
        end

        context 'when the service instance is invalid' do
          context 'because service_instance_guid is invalid' do
            let(:service_instance_guid) { 'THISISWRONG' }

            it 'returns CF-ServiceInstanceNotFound error' do
              post '/v2/service_keys', req

              hash_body = JSON.parse(last_response.body)
              expect(hash_body['error_code']).to eq('CF-ServiceInstanceNotFound')
              expect(last_response.status).to eq(404)
            end
          end

          context 'when the instance operation is in progress' do
            before do
              instance.save_with_new_operation({}, { type: 'delete', state: 'in progress' })
            end

            it 'does not tell the service broker to bind the service' do
              broker = service.service_broker
              post '/v2/service_keys', req

              expect(a_request(:put, %r{#{broker_url(broker)}/v2/service_instances/#{guid_pattern}/service_bindings/#{guid_pattern}})).
                to_not have_been_made
            end

            it 'should show an error message for create key operation' do
              post '/v2/service_keys', req
              expect(last_response).to have_status_code 409
              expect(last_response.body).to match 'AsyncServiceInstanceOperationInProgress'
            end
          end

          describe 'locking the instance as a result of creating service key' do
            context 'when the instance has a previous operation' do
              before do
                instance.service_instance_operation = ServiceInstanceOperation.make(type: 'create', state: 'succeeded')
                instance.save
              end

              it 'reverts the last_operation of the instance to its previous operation' do
                post '/v2/service_keys', req
                expect(instance.last_operation.state).to eq 'succeeded'
                expect(instance.last_operation.type).to eq 'create'
              end
            end

            context 'when the instance does not have a last_operation' do
              before do
                instance.service_instance_operation = nil
                instance.save
              end

              it 'does not save a last_operation' do
                post '/v2/service_keys', req
                expect(instance.refresh.last_operation).to be_nil
              end
            end
          end

          describe 'creating key errors' do
            subject(:make_request) do
              post '/v2/service_keys', req
            end

            context 'when attempting to create key and service key already exists' do
              before do
                ServiceKey.make(name: name, service_instance: instance)
              end

              it 'returns a ServiceKeyNameTaken error' do
                make_request
                expect(last_response.status).to eq(400)
                expect(decoded_response['error_code']).to eq('CF-ServiceKeyNameTaken')
              end

              it 'does not send a bind request to broker' do
                make_request
                expect(a_request(:put, bind_url_regex(service_instance: instance))).to_not have_been_made
              end
            end

            context 'when the v2 broker returns a 409' do
              let(:bind_status) { 409 }
              let(:bind_body) { {} }

              it 'returns a 409' do
                make_request
                expect(last_response).to have_status_code 409
              end

              it 'returns a ServiceBrokerConflict error' do
                make_request
                expect(decoded_response['error_code']).to eq 'CF-ServiceBrokerConflict'
              end
            end

            context 'when the v2 broker returns any other error' do
              let(:bind_status) { 500 }
              let(:bind_body) { { description: 'ERROR MESSAGE HERE' } }

              context 'when the instance has a last_operation' do
                before do
                  instance.service_instance_operation = ServiceInstanceOperation.make(type: 'create', state: 'succeeded')
                end

                it 'rolls back the last_operation of the service instance' do
                  make_request
                  expect(instance.refresh.last_operation.state).to eq 'succeeded'
                  expect(instance.refresh.last_operation.type).to eq 'create'
                end
              end
            end
          end
        end

        context 'when the request includes arbitrary parameters' do
          let(:parameters) { { foo: 'bar' } }
          let(:req) do
            {
              name: name,
              service_instance_guid: service_instance_guid,
              parameters: parameters
            }.to_json
          end

          it 'forwards the parameters in the bind request' do
            post '/v2/service_keys', req
            expect(last_response).to have_status_code 201

            url_regex = %r{#{broker_url(service.service_broker)}/v2/service_instances/#{guid_pattern}/service_bindings/#{guid_pattern}}
            expected_body = { service_id: service.broker_provided_id, plan_id: instance.service_plan.broker_provided_id, parameters: parameters }

            expect(a_request(:put, url_regex).with(body: hash_including(expected_body))).to have_been_made
          end
        end

        context 'when the service instance has been shared' do
          let(:other_space) { Space.make }

          before do
            instance.add_shared_space(other_space)
          end

          context 'when the user is a space developer in the service instance space' do
            it 'returns successfully' do
              post '/v2/service_keys', req
              expect(last_response).to have_status_code(201)
            end
          end

          context 'when the user does not have access to the service instance space' do
            let(:developer) { make_developer_for_space(other_space) }

            it 'returns a 403' do
              post '/v2/service_keys', req
              expect(last_response).to have_status_code(403)
            end
          end
        end

        describe 'asynchronous key creation' do
          context 'when accepts_incomplete is true' do
            before do
              post '/v2/service_keys?accepts_incomplete=true', req
            end

            context 'when bindings_retrievable is true' do
              let(:service) { Service.make(bindings_retrievable: true, service_broker: broker) }

              context 'and the broker returns asynchronously' do
                let(:bind_status) { 202 }
                let(:bind_body) { {} }

                it 'returns a 202 status code' do
                  expect(last_response).to have_status_code(202)
                end

                it 'saves the key in the model' do
                  key = ServiceKey.last
                  expect(key.last_operation.state).to eql('in progress')
                end

                it 'returns an in progress service key response' do
                  expect(decoded_response['entity']['last_operation']['type']).to eq('create')
                  expect(decoded_response['entity']['last_operation']['state']).to eq('in progress')
                end

                it 'returns a location header' do
                  expect(last_response.headers['Location']).to match(%r{^/v2/service_keys/[[:alnum:]-]+$})
                end

                context 'when the service broker returns operation state' do
                  let(:bind_body) { { operation: '123' } }

                  it 'persists the operation state' do
                    key = ServiceKey.last
                    expect(key.last_operation.broker_provided_operation).to eq('123')
                  end
                end
              end

              context 'and the broker is synchronous' do
                let(:bind_status) { 201 }

                it 'returns a 201 status code' do
                  expect(last_response).to have_status_code(201)
                end
              end
            end

            context 'when bindings_retrievable is false' do
              let(:service) { Service.make(bindings_retrievable: false) }

              context 'and the broker returns asynchronously' do
                let(:bind_status) { 202 }
                let(:bind_body) { {} }

                it 'should throw invalid service key error' do
                  expect(last_response).to have_status_code(400)
                  expect(decoded_response['error_code']).to eq 'CF-ServiceKeyInvalid'
                  expect(decoded_response['description']).to match('Could not create asynchronous service key')
                end
              end

              context 'and the broker is synchronous' do
                let(:bind_status) { 201 }

                it 'returns a 201 status code' do
                  expect(last_response).to have_status_code(201)
                end
              end
            end
          end

          context 'when accepts_incomplete is false' do
            it 'returns a 201 status code' do
              post '/v2/service_keys?accepts_incomplete=false', req
              expect(last_response).to have_status_code(201)
            end

            context 'and the broker only supports asynchronous request' do
              let(:bind_status) { 422 }
              let(:bind_body) { { error: 'AsyncRequired' } }

              it 'returns a 400 status code' do
                post '/v2/service_keys?accepts_incomplete=false', req
                expect(last_response).to have_status_code(400)
                expect(decoded_response['error_code']).to eq 'CF-AsyncRequired'
              end
            end
          end

          context 'when accepts_incomplete is not set' do
            context 'and the broker only supports asynchronous request' do
              let(:bind_status) { 422 }
              let(:bind_body) { { error: 'AsyncRequired' } }

              it 'returns a 400 status code' do
                post '/v2/service_keys', req
                expect(last_response).to have_status_code(400)
                expect(decoded_response['error_code']).to eq 'CF-AsyncRequired'
              end
            end
          end

          context 'when accepts_incomplete is not a bool' do
            it 'returns a 400 status code' do
              post '/v2/service_keys?accepts_incomplete=not_a_bool', req
              expect(last_response).to have_status_code(400)

              expect(a_request(:put, %r{#{broker_url(broker)}/v2/service_instances/#{guid_pattern}/service_bindings/#{guid_pattern}})).
                to_not have_been_made
            end
          end
        end
      end

      context 'for a user-provided service instance' do
        let(:instance) { UserProvidedServiceInstance.make }

        it 'returns an error to the user' do
          post '/v2/service_keys', req
          expect(last_response).to have_status_code 400
          expect(decoded_response['description']).to eq('Service keys are not supported for user-provided service instances.')
        end
      end
    end

    describe 'GET', '/v2/service_keys' do
      let(:space)   { Space.make }
      let(:developer) { make_developer_for_space(space) }
      let(:instance_a)  { ManagedServiceInstance.make(space: space) }
      let(:instance_b)  { ManagedServiceInstance.make(space: space) }
      let(:service_key_a) { ServiceKey.make(name: 'fake-key-a', service_instance: instance_a) }
      let(:service_key_b) { ServiceKey.make(name: 'fake-key-b', service_instance: instance_a) }
      let(:service_key_c) { ServiceKey.make(name: 'fake-key-c', service_instance: instance_b) }

      before do
        service_key_a.save
        service_key_b.save
        service_key_c.save
        set_current_user(developer)
      end

      it 'returns the service keys filtered by service_instance_guid' do
        get "/v2/service_keys?q=service_instance_guid:#{instance_a.guid}"
        expect(last_response.status).to eql(200)
        expect(decoded_response.fetch('total_results')).to eq(2)
        expect(decoded_response.fetch('resources').first.fetch('metadata').fetch('guid')).to eq(service_key_a.guid)
        expect(decoded_response.fetch('resources')[1].fetch('metadata').fetch('guid')).to eq(service_key_b.guid)

        get "/v2/service_keys?q=service_instance_guid:#{instance_b.guid}"
        expect(last_response.status).to eql(200)
        expect(decoded_response.fetch('total_results')).to eq(1)
        expect(decoded_response.fetch('resources').first.fetch('metadata').fetch('guid')).to eq(service_key_c.guid)
      end

      it 'returns the service keys filtered by key name' do
        get '/v2/service_keys?q=name:fake-key-a'
        expect(last_response.status).to eql(200)
        expect(decoded_response.fetch('total_results')).to eq(1)
        expect(decoded_response.fetch('resources').first.fetch('metadata').fetch('guid')).to eq(service_key_a.guid)

        get '/v2/service_keys?q=name:non-exist-key-name'
        expect(last_response.status).to eql(200)
        expect(decoded_response.fetch('total_results')).to eq(0)
      end
    end

    describe 'GET', '/v2/service_keys/:service_key_guid' do
      let(:space)   { Space.make }
      let(:developer) { make_developer_for_space(space) }
      let(:instance)  { ManagedServiceInstance.make(space: space) }
      let(:service_key) { ServiceKey.make(name: 'fake-key', service_instance: instance) }

      before { set_current_user(developer) }

      def verify_not_found_response(service_key_guid)
        expect(last_response).to have_status_code 404
        expect(decoded_response.fetch('error_code')).to eq('CF-ServiceKeyNotFound')
        expect(decoded_response.fetch('description')).to eq("The service key could not be found: #{service_key_guid}")
      end

      context 'Not authorized to perform get operation' do
        let(:manager) { make_manager_for_space(instance.space) }
        let(:auditor) { make_auditor_for_space(instance.space) }

        it 'SpaceManager role can not get a service key' do
          set_current_user(manager)
          get "/v2/service_keys/#{service_key.guid}"
          verify_not_found_response(service_key.guid)
        end

        it 'SpaceAuditor role can not get a service key' do
          set_current_user(auditor)
          get "/v2/service_keys/#{service_key.guid}"
          verify_not_found_response(service_key.guid)
        end

        context 'when the user is a developer in a space to which the service instance is shared' do
          let(:other_space) { Space.make }
          let(:developer) { make_developer_for_space(other_space) }

          before do
            instance.add_shared_space(other_space)
          end

          it 'is reports the key as not found' do
            get "/v2/service_keys/#{service_key.guid}"
            verify_not_found_response(service_key.guid)
          end
        end
      end

      context 'when the key is a CredHub reference' do
        let(:service_key) { ServiceKey.make(:credhub_reference, name: 'fake-key', service_instance: instance) }
        let(:credentials) { { 'username' => 'admin_annie', 'password' => 'realsecur3' } }
        let(:fake_credhub_client) { instance_double(Credhub::Client) }

        before do
          allow_any_instance_of(CloudController::DependencyLocator).to receive(:credhub_client).and_return(fake_credhub_client)
        end

        it 'fetches the credential value from CredHub' do
          allow(fake_credhub_client).to receive(:get_credential_by_name).with(service_key.credhub_reference).and_return(credentials)

          get "/v2/service_keys/#{service_key.guid}"

          expect(last_response.status).to eql(200)
          expect(metadata.fetch('guid')).to eq(service_key.guid)
          expect(entity.fetch('credentials')).to eq(credentials)
        end

        it 'returns 503 when credhub is unavailable' do
          allow(fake_credhub_client).to receive(:get_credential_by_name).and_raise(Credhub::Error)

          get "/v2/service_keys/#{service_key.guid}"

          expect(last_response.status).to eq(503)
          expect(decoded_response['description']).to eq('Credential store is unavailable')
        end

        it 'returns 503 when uaa is unavailable' do
          allow(fake_credhub_client).to receive(:get_credential_by_name).and_raise(UaaUnavailable)

          get "/v2/service_keys/#{service_key.guid}"

          expect(last_response.status).to eq(503)
          expect(decoded_response['description']).to eq('The UAA service is currently unavailable')
        end
      end

      context 'when the key is not a CredHub reference' do
        it 'returns the specific service key' do
          get "/v2/service_keys/#{service_key.guid}"
          expect(last_response.status).to eql(200)
          expect(decoded_response.fetch('metadata').fetch('guid')).to eq(service_key.guid)
          expect(entity.fetch('credentials')).to eq(service_key.credentials)
        end
      end

      it 'returns empty result if no service key found' do
        get '/v2/service_keys/non-exist-service-key-guid'
        expect(last_response.status).to eql(404)
        expect(decoded_response.fetch('error_code')).to eq('CF-ServiceKeyNotFound')
        expect(decoded_response.fetch('description')).to eq('The service key could not be found: non-exist-service-key-guid')
      end
    end

    describe 'DELETE', '/v2/service_keys/:service_key_guid' do
      let(:service_key) { ServiceKey.make }
      let(:instance) { service_key.service_instance }
      let(:broker) { instance.service_plan.service.service_broker }
      let(:developer) { make_developer_for_space(instance.space) }

      before do
        stub_requests(instance.service.service_broker)
        set_current_user(developer, email: 'example@example.com')
      end

      def verify_not_found_response(service_key_guid)
        expect(last_response).to have_status_code 404
        expect(decoded_response.fetch('error_code')).to eq('CF-ServiceKeyNotFound')
        expect(decoded_response.fetch('description')).to eq("The service key could not be found: #{service_key_guid}")
      end

      context 'Not authorized to perform delete operation' do
        let(:manager) { make_manager_for_space(instance.space) }
        let(:auditor) { make_auditor_for_space(instance.space) }

        it 'SpaceManager role can not delete a service key' do
          set_current_user(manager)
          delete "/v2/service_keys/#{service_key.guid}"
          verify_not_found_response(service_key.guid)
        end

        it 'SpaceAuditor role can not delete a service key' do
          set_current_user(auditor)
          delete "/v2/service_keys/#{service_key.guid}"
          verify_not_found_response(service_key.guid)
        end

        context 'when the user is a developer in a space to which the service instance is shared' do
          let(:other_space) { Space.make }
          let(:developer) { make_developer_for_space(other_space) }

          before do
            instance.add_shared_space(other_space)
          end

          it 'is reports the key as not found' do
            delete "/v2/service_keys/#{service_key.guid}"
            verify_not_found_response(service_key.guid)
          end
        end
      end

      it 'returns ServiceKeyNotFound error if there is no such key' do
        delete '/v2/service_keys/non-exist-service-key'
        verify_not_found_response('non-exist-service-key')
      end

      it 'deletes the service key' do
        expect {
          delete "/v2/service_keys/#{service_key.guid}"
        }.to change(ServiceKey, :count).by(-1)
        expect(last_response).to have_status_code 204
        expect(last_response.body).to be_empty
        expect { service_key.refresh }.to raise_error Sequel::Error, 'Record not found'
      end

      context 'when the broker returns an error' do
        let(:unbind_status) { 500 }
        let(:unbind_body) { { description: 'ERROR MESSAGE HERE' } }

        it 'returns a 502 status code ' do
          delete "/v2/service_keys/#{service_key.guid}"
          expect(last_response).to have_status_code(502)
          expect(decoded_response['error_code']).to eq 'CF-ServiceBrokerBadResponse'

          expect(ServiceKey.find(guid: service_key.guid)).to exist
        end
      end

      it 'creates an audit event after a service key deleted' do
        delete "/v2/service_keys/#{service_key.guid}"

        event = Event.first(type: 'audit.service_key.delete')
        expect(event.actor_type).to eq('user')
        expect(event.timestamp).to be
        expect(event.actor).to eq(developer.guid)
        expect(event.actor_name).to eq('example@example.com')
        expect(event.actee).to eq(service_key.guid)
        expect(event.actee_type).to eq('service_key')
        expect(event.actee_name).to eq(service_key.name)
        expect(event.space_guid).to eq(service_key.space.guid)
        expect(event.organization_guid).to eq(service_key.space.organization.guid)
        expect(event.metadata).to include({ 'request' => {} })
      end

      describe 'asynchronous key deletion' do
        context 'when accepts_incomplete is true' do
          context 'when the broker responds asynchronously' do
            let(:unbind_status) { 202 }

            it 'returns a 202 status code' do
              delete "/v2/service_keys/#{service_key.guid}?accepts_incomplete=true"
              expect(last_response).to have_status_code(202)
            end

            it 'passess accepts_incomplete flag to the broker' do
              delete "/v2/service_keys/#{service_key.guid}?accepts_incomplete=true"
              expect(a_request(:delete, unbind_url(service_key, accepts_incomplete: true))).to have_been_made
            end

            it 'updates the service key operation in the model' do
              delete "/v2/service_keys/#{service_key.guid}?accepts_incomplete=true"

              service_key.reload

              expect(service_key.last_operation.type).to eql('delete')
              expect(service_key.last_operation.state).to eql('in progress')
            end

            it 'indicates the service key is being deleted' do
              delete "/v2/service_keys/#{service_key.guid}?accepts_incomplete=true"

              expect(last_response.headers['Location']).to eq "/v2/service_keys/#{service_key.guid}"

              expect(decoded_response['entity']['last_operation']).to be
              expect(decoded_response['entity']['last_operation']['type']).to eq('delete')
              expect(decoded_response['entity']['last_operation']['state']).to eq('in progress')
            end
          end

          context 'when the broker responds synchronously' do
            let(:unbind_status) { 200 }
            let(:unbind_body) { {} }

            it 'returns 204 status code' do
              delete "/v2/service_keys/#{service_key.guid}?accepts_incomplete=true"

              expect(last_response).to have_status_code(204)
            end
          end
        end

        context 'when accepts_incomplete is false' do
          it 'returns a 204 status code' do
            delete "/v2/service_keys/#{service_key.guid}?accepts_incomplete=false"
            expect(last_response).to have_status_code(204)
          end

          context 'when the broker responds asynchronously' do
            let(:unbind_status) { 202 }
            let(:params_warning) do
              CGI.escape(['The service broker responded asynchronously to the unbind request, but the accepts_incomplete query parameter was false or not given.',
                          'The service key may not have been successfully deleted on the service broker.'].join(' '))
            end

            it 'returns a 204 status code' do
              delete "/v2/service_keys/#{service_key.guid}?accepts_incomplete=false"

              expect(last_response).to have_status_code(204)
            end

            it 'should warn the user about the misbehave broker' do
              delete "/v2/service_keys/#{service_key.guid}?accepts_incomplete=false"

              expect(last_response.headers).to include('X-Cf-Warnings')
              expect(last_response.headers['X-Cf-Warnings']).to include(params_warning)
            end
          end

          context 'and the broker only supports asynchronous request' do
            let(:unbind_status) { 422 }
            let(:unbind_body) { { error: 'AsyncRequired' } }

            it 'returns a 400 status code' do
              delete "/v2/service_keys/#{service_key.guid}?accepts_incomplete=false"
              expect(last_response).to have_status_code(400)
              expect(decoded_response['error_code']).to eq 'CF-AsyncRequired'
            end
          end
        end

        context 'and when accepts_incomplete is not set' do
          context 'and when the broker only supports asynchronous request' do
            let(:unbind_status) { 422 }
            let(:unbind_body) { { error: 'AsyncRequired' } }

            it 'returns a 400 status code' do
              delete "/v2/service_keys/#{service_key.guid}"
              expect(last_response).to have_status_code(400)
              expect(decoded_response['error_code']).to eq 'CF-AsyncRequired'
            end
          end
        end

        context 'and when the parameter is not a bool' do
          it 'returns a 400 status code' do
            delete "/v2/service_keys/#{service_key.guid}?accepts_incomplete=not_a_bool"
            expect(last_response).to have_status_code(400)

            expect(a_request(:delete, %r{#{broker_url(broker)}/v2/service_instances/#{guid_pattern}/service_keys/#{guid_pattern}})).
              to_not have_been_made
          end
        end
      end
    end

    describe 'GET', '/v2/service_keys/:service_key_guid/parameters' do
      let(:space) { Space.make }
      let(:developer) { make_developer_for_space(space) }

      before do
        set_current_user(developer)
      end

      context 'when the service key is for managed service instance' do
        let(:service_plan) { ServicePlan.make(service: service) }
        let(:managed_service_instance) { ManagedServiceInstance.make(space: space, service_plan: service_plan) }

        context 'when the service has bindings_retrievable set to false' do
          let(:service) { Service.make(bindings_retrievable: false) }

          it 'returns a 400' do
            service_key = ServiceKey.make(service_instance: managed_service_instance)

            get "/v2/service_keys/#{service_key.guid}/parameters"
            expect(last_response.status).to eql(400)
            expect(last_response.body).to include('This service does not support fetching service key parameters.')
          end
        end

        context 'when the service has bindings_retrievable not set' do
          let(:service) { Service.make }

          it 'returns a 400' do
            service_key = ServiceKey.make(service_instance: managed_service_instance)

            get "/v2/service_keys/#{service_key.guid}/parameters"
            expect(last_response.status).to eql(400)
            expect(last_response.body).to include('This service does not support fetching service key parameters.')
          end
        end

        context 'when the service has bindings_retrievable set to true' do
          let(:service) { Service.make(bindings_retrievable: true) }
          let(:broker) { service.service_broker }
          let(:service_key) { ServiceKey.make(service_instance: managed_service_instance) }
          let(:body) { { 'parameters' => { 'foo' => true } }.to_json }
          let(:response_code) { 200 }

          before do
            stub_request(:get, %r{#{broker_url(broker)}/v2/service_instances/#{guid_pattern}/service_bindings/#{guid_pattern}}).
              with(basic_auth: basic_auth(service_broker: broker)).
              to_return(status: response_code, body: body)
          end

          context 'when the broker returns the parameters' do
            it 'returns the parameters' do
              get "/v2/service_keys/#{service_key.guid}/parameters"
              expect(last_response.status).to eql(200)
              expect(last_response.body).to eql({ 'foo' => true }.to_json)
            end
          end

          context 'when the broker returns empty object' do
            let(:body) { {}.to_json }

            it 'returns the parameters' do
              get "/v2/service_keys/#{service_key.guid}/parameters"
              expect(last_response.status).to eql(200)
              expect(last_response.body).to eql({}.to_json)
            end
          end

          context 'when the brokers response is missing a parameters key but contains other keys' do
            let(:body) { { 'credentials' => {} }.to_json }

            it 'returns an empty object' do
              get "/v2/service_keys/#{service_key.guid}/parameters"
              expect(last_response.status).to eql(200)
              expect(last_response.body).to eql({}.to_json)
            end
          end

          context 'when the broker returns invalid json as per the spec' do
            let(:body) { { "parameters": 'blahblah' }.to_json }

            it 'returns 502' do
              get "/v2/service_keys/#{service_key.guid}/parameters"
              expect(last_response.status).to eql(502)
              hash_body = JSON.parse(last_response.body)
              expect(hash_body['error_code']).to eq('CF-ServiceBrokerResponseMalformed')
            end
          end

          context 'when the broker returns invalid json' do
            let(:body) { '{]' }

            it 'returns 502' do
              get "/v2/service_keys/#{service_key.guid}/parameters"
              expect(last_response.status).to eql(502)
              hash_body = JSON.parse(last_response.body)
              expect(hash_body['error_code']).to eq('CF-ServiceBrokerResponseMalformed')
            end
          end

          context 'when the broker returns a non-spec HTTP error code' do
            let(:response_code) { 500 }

            it 'returns a 502 and an error' do
              get "/v2/service_keys/#{service_key.guid}/parameters"

              expect(last_response.status).to eql(502)
              hash_body = JSON.parse(last_response.body)
              expect(hash_body['error_code']).to eq('CF-ServiceBrokerBadResponse')
            end
          end

          context 'when the broker returns 404 error code' do
            let(:response_code) { 404 }

            it 'returns a 502 and an error' do
              get "/v2/service_keys/#{service_key.guid}/parameters"

              expect(last_response.status).to eql(502)
              hash_body = JSON.parse(last_response.body)
              expect(hash_body['error_code']).to eq('CF-ServiceBrokerRequestRejected')
            end
          end

          context 'user permissions' do
            let(:user) { User.make }
            let(:body) { {}.to_json }

            {
              'admin'               => 200,
              'space_developer'     => 200,
              'admin_read_only'     => 200,
              'global_auditor'      => 404,
              'space_manager'       => 404,
              'space_auditor'       => 404,
              'org_manager'         => 404,
              'org_auditor'         => 404,
              'org_billing_manager' => 404,
              'org_user'            => 404,
            }.each do |role, expected_status|
              context "as a(n) #{role} in the binding space" do
                before do
                  set_current_user_as_role(
                    role:   role,
                    org:    space.organization,
                    space:  space,
                    user:   user
                  )
                end

                it "receives a #{expected_status} http status code" do
                  get "/v2/service_keys/#{service_key.guid}/parameters"
                  expect(last_response.status).to eq(expected_status)
                end
              end
            end
          end

          context 'when the service key guid is invalid' do
            it 'returns a 404' do
              get '/v2/service_keys/some-bogus-guid/parameters'
              expect(last_response.status).to eql(404)
              expect(last_response.body).to include('The service key could not be found: some-bogus-guid')
            end
          end
        end
      end
      context 'when the key is for a user provided service' do
        let(:user_provided_service_instance) { UserProvidedServiceInstance.make(space: space) }

        it 'returns a 400' do
          service_key = ServiceKey.make(service_instance: user_provided_service_instance)

          get "/v2/service_keys/#{service_key.guid}/parameters"
          expect(last_response.status).to eql(400)
          expect(last_response.body).to include('This service does not support fetching service key parameters.')
        end
      end
    end
  end
end
