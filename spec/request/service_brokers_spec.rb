require 'spec_helper'
require 'request_spec_shared_examples'
require 'cloud_controller'
require 'services'

RSpec.describe 'V3 service brokers' do
  let(:user) { VCAP::CloudController::User.make }
  let(:global_broker_id) { 'global-service-id' }
  let(:space_broker_id) { 'space-service-id' }
  let(:org) { VCAP::CloudController::Organization.make }
  let(:space) { VCAP::CloudController::Space.make(organization: org) }
  let(:space_developer_alternate_space_headers) {
    user = VCAP::CloudController::User.make
    space = VCAP::CloudController::Space.make(organization: org)
    org.add_user(user)
    space.add_developer(user)

    headers_for(user)
  }
  let(:global_broker_request_body) do
    {
        name: 'broker name',
        url: 'http://example.org/broker-url',
        credentials: {
            type: 'basic',
            data: {
                username: 'admin',
                password: 'welcome',
            }
        }
    }
  end
  let(:space_scoped_broker_request_body) do
    {
        name: 'space-scoped broker name',
        url: 'http://example.org/space-broker-url',
        credentials: {
            type: 'basic',
            data: {
                username: 'admin',
                password: 'welcome',
            },
        },
        relationships: {
            space: {
                data: {
                    guid: space.guid
                },
            },
        },
    }
  end

  before do
    stub_request(:get, 'http://example.org/broker-url/v2/catalog').
      to_return(status: 200, body: catalog.to_json, headers: {})
    stub_request(:get, 'http://example.org/space-broker-url/v2/catalog').
      to_return(status: 200, body: catalog(space_broker_id).to_json, headers: {})
    stub_request(:put, %r{http://example.org/broker-url/v2/service\_instances/.*}).
      to_return(status: 200, body: '{}', headers: {})

    token = { token_type: 'Bearer', access_token: 'my-favourite-access-token' }
    stub_request(:post, 'https://uaa.service.cf.internal/oauth/token').
      to_return(status: 200, body: token.to_json, headers: { 'Content-Type' => 'application/json' })

    stub_uaa_for(global_broker_id)
    stub_uaa_for(space_broker_id)
  end

  describe 'GET /v3/service_brokers' do
    let(:api_call) { lambda { |user_headers| get '/v3/service_brokers', nil, user_headers } }

    context 'when there are no service brokers' do
      let(:expected_codes_and_responses) do
        h = Hash.new(
          code: 200,
          response_objects: []
        )

        h
      end

      it_behaves_like 'permissions for list endpoint', ALL_PERMISSIONS
    end

    context 'when there are global service brokers' do
      let!(:global_service_broker1) { VCAP::CloudController::ServiceBroker.make }
      let!(:global_service_broker2) { VCAP::CloudController::ServiceBroker.make }

      let(:global_service_broker1_json) do
        {
            guid: global_service_broker1.guid,
            name: global_service_broker1.name,
            url: global_service_broker1.broker_url,
            created_at: iso8601,
            updated_at: iso8601,
            status: 'available',
            available: true,
            relationships: {},
            links: { self: { href: %r(#{Regexp.escape(link_prefix)}\/v3\/service_brokers\/#{global_service_broker1.guid}) } }
        }
      end
      let(:global_service_broker2_json) do
        {
            guid: global_service_broker2.guid,
            name: global_service_broker2.name,
            url: global_service_broker2.broker_url,
            created_at: iso8601,
            updated_at: iso8601,
            status: 'unknown',
            available: false,
            relationships: {},
            links: { self: { href: %r(#{Regexp.escape(link_prefix)}\/v3\/service_brokers\/#{global_service_broker2.guid}) } }
        }
      end

      let!(:broker_state) { VCAP::CloudController::ServiceBrokerState.make_unsaved }

      before do
        global_service_broker1.update(service_broker_state: broker_state)
      end

      let(:expected_codes_and_responses) do
        h = Hash.new(
          code: 200,
          response_objects: []
        )

        h['admin'] = { code: 200, response_objects: [global_service_broker1_json, global_service_broker2_json] }
        h['admin_read_only'] = { code: 200, response_objects: [global_service_broker1_json, global_service_broker2_json] }
        h['global_auditor'] = { code: 200, response_objects: [global_service_broker1_json, global_service_broker2_json] }

        h
      end

      it_behaves_like 'permissions for list endpoint', ALL_PERMISSIONS
    end

    context 'when there are spaced-scoped service brokers' do
      let!(:space_scoped_service_broker) { VCAP::CloudController::ServiceBroker.make(space: space) }
      let(:space_scoped_service_broker_json) do
        {
            guid: space_scoped_service_broker.guid,
            name: space_scoped_service_broker.name,
            url: space_scoped_service_broker.broker_url,
            created_at: iso8601,
            updated_at: iso8601,
            status: 'unknown',
            available: false,
            relationships: {
                space: { data: { guid: space.guid } }
            },
            links: {
                self: {
                    href: %r(#{Regexp.escape(link_prefix)}\/v3\/service_brokers\/#{space_scoped_service_broker.guid})
                },
                space: {
                    href: %r(#{Regexp.escape(link_prefix)}\/v3\/spaces\/#{space.guid})
                }
            }
        }
      end
      let(:expected_codes_and_responses) do
        h = Hash.new(
          code: 200,
          response_objects: []
        )

        h['admin'] = {
            code: 200,
            response_objects: [space_scoped_service_broker_json]
        }
        h['admin_read_only'] = {
            code: 200,
            response_objects: [space_scoped_service_broker_json]
        }
        h['global_auditor'] = {
            code: 200,
            response_objects: [space_scoped_service_broker_json]
        }
        h['space_developer'] = { code: 200,
            response_objects: [space_scoped_service_broker_json]
        }

        h
      end

      it_behaves_like 'permissions for list endpoint', ALL_PERMISSIONS

      it 'returns 200 OK and an empty list of brokers for space developer in another space' do
        expect_empty_list(space_developer_alternate_space_headers)
      end
    end

    context 'filters and sorting' do
      let!(:global_service_broker) {
        VCAP::CloudController::ServiceBroker.make(name: 'test-broker-foo')
      }

      let!(:space_scoped_service_broker) {
        VCAP::CloudController::ServiceBroker.make(name: 'test-broker-bar', space: space)
      }

      context 'when requesting one broker per page' do
        it 'returns 200 OK and a body containing one broker with pagination information for the next' do
          expect_filtered_brokers('per_page=1', [global_service_broker])

          expect(parsed_response['pagination']['total_results']).to eq(2)
          expect(parsed_response['pagination']['total_pages']).to eq(2)
        end
      end

      context 'when requesting with a specific order by name' do
        context 'in ascending order' do
          it 'returns 200 OK and a body containg the brokers ordered by created at time' do
            expect_filtered_brokers('order_by=name', [space_scoped_service_broker, global_service_broker])
          end
        end

        context 'descending order' do
          it 'returns 200 OK and a body containg the brokers ordered by created at time' do
            expect_filtered_brokers('order_by=-name', [global_service_broker, space_scoped_service_broker])
          end
        end

        context 'when requesting with a space guid filter' do
          it 'returns 200 OK and a body containing one broker matching the space guid filter' do
            expect_filtered_brokers("space_guids=#{space.guid}", [space_scoped_service_broker])
          end
        end

        context 'when requesting with a space guid filter for another space guid' do
          it 'returns 200 OK and a body containing no brokers' do
            expect_filtered_brokers('space_guids=random-space-guid', [])
          end
        end

        context 'when requesting with a names filter' do
          it 'returns 200 OK and a body containing one broker matching the names filter' do
            expect_filtered_brokers("names=#{global_service_broker.name}", [global_service_broker])
          end
        end
      end
    end

    def expect_filtered_brokers(filter, list)
      get("/v3/service_brokers?#{filter}", {}, admin_headers)

      expect(last_response).to have_status_code(200)
      expect(parsed_response.fetch('resources').length).to eq(list.length)

      list.each_with_index do |broker, index|
        expect(parsed_response['resources'][index]['name']).to eq(broker.name)
      end
    end

    def expect_empty_list(user_headers)
      get('/v3/service_brokers', {}, user_headers)

      expect(last_response).to have_status_code(200)

      expect(parsed_response).to have_key('resources')
      expect(parsed_response['resources'].length).to eq(0)
    end
  end

  describe 'GET /v3/service_brokers/:guid' do
    context 'when the service broker does not exist' do
      it 'return with 404 Not Found' do
        is_expected.to_not find_broker(broker_guid: 'does-not-exist', with: admin_headers)
      end
    end

    context 'when the service broker is global' do
      let!(:global_service_broker1) { VCAP::CloudController::ServiceBroker.make }
      let(:api_call) { lambda { |user_headers| get "/v3/service_brokers/#{global_service_broker1.guid}", nil, user_headers } }

      let(:global_service_broker1_json) do
        {
            guid: global_service_broker1.guid,
            name: global_service_broker1.name,
            url: global_service_broker1.broker_url,
            created_at: iso8601,
            updated_at: iso8601,
            status: 'unknown',
            available: false,
            relationships: {},
            links: { self: { href: %r(#{Regexp.escape(link_prefix)}\/v3\/service_brokers\/#{global_service_broker1.guid}) } }
        }
      end

      let(:expected_codes_and_responses) do
        h = Hash.new(code: 404)

        h['admin'] = {
            code: 200,
            response_object: global_service_broker1_json
        }
        h['admin_read_only'] = {
            code: 200,
            response_object: global_service_broker1_json
        }
        h['global_auditor'] = {
            code: 200,
            response_object: global_service_broker1_json
        }

        h
      end

      it_behaves_like 'permissions for single object endpoint', ALL_PERMISSIONS
    end

    context 'when the service broker is space scoped' do
      let!(:space_scoped_service_broker) { VCAP::CloudController::ServiceBroker.make(space: space) }
      let(:api_call) { lambda { |user_headers| get "/v3/service_brokers/#{space_scoped_service_broker.guid}", nil, user_headers } }

      let(:space_scoped_service_broker_json) do
        {
            guid: space_scoped_service_broker.guid,
            name: space_scoped_service_broker.name,
            url: space_scoped_service_broker.broker_url,
            created_at: iso8601,
            updated_at: iso8601,
            status: 'unknown',
            available: false,
            relationships: {
                space: { data: { guid: space.guid } }
            },
            links: {
                self: {
                    href: %r(#{Regexp.escape(link_prefix)}\/v3\/service_brokers\/#{space_scoped_service_broker.guid})
                },
                space: {
                    href: %r(#{Regexp.escape(link_prefix)}\/v3\/spaces\/#{space.guid})
                }
            }
        }
      end
      let(:expected_codes_and_responses) do
        h = Hash.new(code: 404)

        h['admin'] = {
            code: 200,
            response_object: space_scoped_service_broker_json
        }
        h['admin_read_only'] = {
            code: 200,
            response_object: space_scoped_service_broker_json
        }
        h['global_auditor'] = {
            code: 200,
            response_object: space_scoped_service_broker_json
        }
        h['space_developer'] = {
            code: 200,
            response_object: space_scoped_service_broker_json
        }

        h
      end

      it_behaves_like 'permissions for single object endpoint', ALL_PERMISSIONS

      it 'returns 404 Not Found for space developer in another space' do
        is_expected.to_not find_broker(broker_guid: space_scoped_service_broker.guid, with: space_developer_alternate_space_headers)
      end
    end
  end

  describe 'POST /v3/service_brokers' do
    let(:global_service_broker) do
      {
          guid: UUID_REGEX,
          name: 'broker name',
          url: 'http://example.org/broker-url',
          created_at: iso8601,
          updated_at: iso8601,
          status: 'synchronization in progress',
          available: false,
          relationships: {},
          links: { self: { href: %r(#{Regexp.escape(link_prefix)}\/v3\/service_brokers\/#{UUID_REGEX}) } }
      }
    end

    context 'global service broker' do
      it_behaves_like 'permissions for single object endpoint', ALL_PERMISSIONS do
        let(:api_call) { lambda { |user_headers| post '/v3/service_brokers', global_broker_request_body.to_json, user_headers } }
        let(:expected_codes_and_responses) do
          Hash.new(code: 403).tap do |h|
            h['admin'] = { code: 202 }
          end
        end

        let(:after_request_check) { lambda { assert_broker_state(global_service_broker) } }

        let(:expected_events) do
          lambda do |email|
            [
              { type: 'audit.service.create', actor: 'broker name' },
              { type: 'audit.service.create', actor: 'broker name' },
              { type: 'audit.service_broker.create', actor: email },
              { type: 'audit.service_dashboard_client.create', actor: 'broker name' },
              { type: 'audit.service_plan.create', actor: 'broker name' },
              { type: 'audit.service_plan.create', actor: 'broker name' }
            ]
          end
        end
      end
    end

    context 'space-scoped service broker' do
      let(:space_scoped_service_broker) do
        {
            guid: UUID_REGEX,
            name: 'space-scoped broker name',
            url: 'http://example.org/space-broker-url',
            created_at: iso8601,
            updated_at: iso8601,
            status: 'synchronization in progress',
            available: false,
            relationships: {
                space: { data: { guid: space.guid } }
            },
            links: {
                self: {
                    href: %r(#{Regexp.escape(link_prefix)}\/v3\/service_brokers\/#{UUID_REGEX})
                },
                space: {
                    href: %r(#{Regexp.escape(link_prefix)}\/v3\/spaces\/#{space.guid})
                }
            }
        }
      end

      it_behaves_like 'permissions for single object endpoint', LOCAL_ROLES do
        let(:api_call) { lambda { |user_headers| post '/v3/service_brokers', space_scoped_broker_request_body.to_json, user_headers } }

        let(:expected_codes_and_responses) {
          Hash.new(code: 422).tap do |h|
            h['space_developer'] = { code: 202 }
            h['space_auditor'] = { code: 403 }
            h['space_manager'] = { code: 403 }
            h['org_manager'] = { code: 403 }
          end
        }

        let(:after_request_check) do
          lambda do
            assert_broker_state(space_scoped_service_broker)
          end
        end
      end
    end

    context 'when the job succeeds' do
      before do
        create_broker_successfully(global_broker_request_body, with: admin_headers)
        execute_all_jobs(expected_successes: 1, expected_failures: 0)
      end

      let(:tx_url) { VCAP::CloudController::Config.config.get(:uaa, :internal_url) + '/oauth/clients/tx/modify' }

      it 'creates some UAA dashboard clients' do
        expect(a_request(:post, tx_url)).to have_been_made
      end
    end

    context 'when the job fails to execute' do
      before do
        # Disabling route and volume services makes the job execution fail
        TestConfig.config[:route_services_enabled] = false
        TestConfig.config[:volume_services_enabled] = false

        create_broker_successfully(global_broker_request_body, with: admin_headers)
        execute_all_jobs(expected_successes: 0, expected_failures: 1)
      end

      let(:uaa_uri) { VCAP::CloudController::Config.config.get(:uaa, :internal_url) }
      let(:tx_url) { uaa_uri + '/oauth/clients/tx/modify' }

      it 'updates the job status' do
        job_url = last_response['Location']
        get job_url, {}, admin_headers
        expect(parsed_response).to include({
            'state' => 'FAILED',
            'operation' => 'service_broker.catalog.synchronize',
            'errors' => [
              include({
                  'detail' => "Service broker catalog is incompatible: \n" \
                "Service route_volume_service_name-2 is declared to be a route service but support for route services is disabled.\n" \
                "Service route_volume_service_name-2 is declared to be a volume mount service but support for volume mount services is disabled.\n",
                  'title' => 'CF-ServiceBrokerCatalogIncompatible',
                  'code' => 270019
              })
            ],
            'links' => {
                'self' => {
                    'href' => job_url
                },
                'service_brokers' => {
                    'href' => match(%r(http.+/v3/service_brokers/[^/]+))
                }
            }
        })
      end

      it 'does not synchronize the broker catalog' do
        service_broker = VCAP::CloudController::ServiceBroker.last
        services = VCAP::CloudController::Service.where(service_broker_id: service_broker.id)
        expect(services).to be_empty
      end

      it 'updates the broker status' do
        expect_broker_status(
          available: false,
          status: 'synchronization failed',
          with: admin_headers
        )
      end

      it 'does not create any UAA dashboard clients' do
        expect(a_request(:post, tx_url)).not_to have_been_made
      end
    end
    let(:global_broker_with_identical_name_body) {
      {
          name: global_broker_request_body[:name],
          url: 'http://example.org/different-broker-url',
          credentials: global_broker_request_body[:credentials]
      }
    }
    let(:global_broker_with_identical_url_body) {
      {
          name: 'different broker name',
          url: global_broker_request_body[:url],
          credentials: global_broker_request_body[:credentials]
      }
    }

    context 'when fetching broker catalog fails' do
      before do
        stub_request(:get, 'http://example.org/broker-url/v2/catalog').
          to_return(status: 418, body: {}.to_json)

        create_broker_successfully(global_broker_request_body, with: admin_headers)

        execute_all_jobs(expected_successes: 0, expected_failures: 1)
      end

      it 'leaves broker in a non-available failed state' do
        expect_broker_status(
          available: false,
          status: 'synchronization failed',
          with: admin_headers
        )
      end

      it 'has failed the job with an appropriate error' do
        job_url = last_response['Location']
        get job_url, {}, admin_headers
        expect(parsed_response).to include({
            'state' => 'FAILED',
            'operation' => 'service_broker.catalog.synchronize',
            'errors' => [
              include(
                'code' => 10001,
                  'detail' => "The service broker rejected the request to http://example.org/broker-url/v2/catalog. Status Code: 418 I'm a Teapot, Body: {}"
              )
            ],
            'links' => {
                'self' => {
                    'href' => job_url
                },
                'service_brokers' => {
                    'href' => match(%r(http.+/v3/service_brokers/[^/]+))
                }
            }
        })
      end
    end

    context 'when catalog is not valid' do
      before do
        stub_request(:get, 'http://example.org/broker-url/v2/catalog').
          to_return(status: 200, body: {}.to_json)

        create_broker_successfully(global_broker_request_body, with: admin_headers)

        execute_all_jobs(expected_successes: 0, expected_failures: 1)
      end

      it 'leaves broker in a non-available failed state' do
        expect_broker_status(
          available: false,
          status: 'synchronization failed',
          with: admin_headers
        )
      end

      it 'has failed the job with an appropriate error' do
        job_url = last_response['Location']
        get job_url, {}, admin_headers
        expect(parsed_response).to include({
            'state' => 'FAILED',
            'operation' => 'service_broker.catalog.synchronize',
            'errors' => [
              include(
                'code' => 270012,
                  'detail' => "Service broker catalog is invalid: \nService broker must provide at least one service\n"
              )
            ],
            'links' => {
                'self' => {
                    'href' => job_url
                },
                'service_brokers' => {
                    'href' => match(%r(http.+/v3/service_brokers/[^/]+))
                }
            }
        })
      end
    end

    context 'when synchronizing UAA clients fails' do
      before do
        VCAP::CloudController::ServiceDashboardClient.make(
          uaa_id: dashboard_client['id']
        )

        create_broker_successfully(global_broker_request_body, with: admin_headers)

        execute_all_jobs(expected_successes: 0, expected_failures: 1)
      end

      let(:job) { VCAP::CloudController::PollableJobModel.last }

      it 'leaves broker in a non-available failed state' do
        expect_broker_status(
          available: false,
          status: 'synchronization failed',
          with: admin_headers
        )
      end

      it 'has failed the job with an appropriate error' do
        get "/v3/jobs/#{job.guid}", {}, admin_headers
        expect(parsed_response).to include(
          'state' => 'FAILED',
          'operation' => 'service_broker.catalog.synchronize',
          'errors' => [
            include(
              'code' => 270012,
              'detail' => "Service broker catalog is invalid: \nService service_name-1\n  Service dashboard client id must be unique\n"
              )
          ],
          'links' => {
              'self' => {
                  'href' => match(%r(http.+/v3/jobs/#{job.guid}))
              },
              'service_brokers' => {
                  'href' => match(%r(http.+/v3/service_brokers/[^/]+))
              }
          }
        )
      end
    end

    context 'when user provides a malformed request' do
      let(:malformed_body) do
        {
            whatever: 'oopsie'
        }
      end

      it 'responds with a helpful error message' do
        create_broker(malformed_body, with: admin_headers)

        expect(last_response).to have_status_code(422)
        expect(last_response.body).to include('UnprocessableEntity')
        expect(last_response.body).to include('Name must be a string')
      end
    end

    context 'when a broker with the same name exists' do
      before do
        VCAP::CloudController::ServiceBroker.make(name: global_broker_request_body[:name])
        create_broker(global_broker_with_identical_name_body, with: admin_headers)
      end

      it 'should return 422 and meaningful error and does not create a broker' do
        expect_no_broker_created
        expect_error(status: 422, error: 'UnprocessableEntity', description: 'Name must be unique')
      end
    end

    context 'when another broker with the same name gets created whilst current one is in progress' do
      before do
        create_broker_successfully(global_broker_request_body, with: admin_headers)
        create_broker(global_broker_with_identical_name_body, with: admin_headers)
      end

      it 'should return 422 and meaningful error and does not create a broker' do
        expect_no_broker_created
        expect_error(status: 422, error: 'UnprocessableEntity', description: 'Name must be unique')
      end
    end

    context 'when another broker with the same URL gets created whilst current one is in progress' do
      before do
        create_broker_successfully(global_broker_request_body, with: admin_headers)
        create_broker(global_broker_with_identical_url_body, with: admin_headers)
      end

      it 'should return 202 Accepted and broker created' do
        expect(last_response).to have_status_code(202)
        expect_created_broker(global_broker_with_identical_url_body)
      end
    end

    def expect_created_broker(expected_broker)
      expect(VCAP::CloudController::ServiceBroker.count).to eq(@count_before_creation + 1)

      service_broker = VCAP::CloudController::ServiceBroker.last

      expect(service_broker).to include(
        'name' => expected_broker[:name],
        'broker_url' => expected_broker[:url],
        'auth_username' => expected_broker.dig(:credentials, :data, :username),
        'space_guid' => expected_broker.dig(:relationships, :space, :data, :guid),
      )

      # asserting password separately because it is not exported in to_hash
      expect(service_broker.auth_password).to eq(expected_broker[:credentials][:data][:password])
    end

    def expect_broker_status(available:, status:, with:)
      expect(VCAP::CloudController::ServiceBroker.count).to eq(@count_before_creation + 1)
      service_broker = VCAP::CloudController::ServiceBroker.last

      get("/v3/service_brokers/#{service_broker.guid}", {}, with)
      expect(last_response.status).to eq(200)
      expect(parsed_response).to include(
        'available' => available,
        'status' => status
      )
    end

    def expect_no_broker_created
      expect(VCAP::CloudController::ServiceBroker.count).to eq(@count_before_creation)
    end

    def assert_broker_state(broker_json)
      job_location = last_response.headers['Location']
      get job_location, {}, admin_headers
      expect(last_response.status).to eq(200)
      broker_url = parsed_response.dig('links', 'service_brokers', 'href')

      get broker_url, {}, admin_headers
      expect(last_response.status).to eq(200)
      expect(parsed_response).to match_json_response(broker_json)

      execute_all_jobs(expected_successes: 1, expected_failures: 0)

      get broker_url, {}, admin_headers
      expect(last_response.status).to eq(200)

      updated_service_broker_json = broker_json.tap do |broker|
        broker[:status] = 'available'
        broker[:available] = true
      end

      expect(parsed_response).to match_json_response(updated_service_broker_json)
    end
  end

  describe 'DELETE /v3/service_brokers/:guid' do
    let!(:global_broker) {
      create_broker_successfully(global_broker_request_body, with: admin_headers, execute_all_jobs: true)
    }
    let!(:global_broker_services) { VCAP::CloudController::Service.where(service_broker_id: global_broker.id) }
    let!(:global_broker_plans) { VCAP::CloudController::ServicePlan.where(service_id: global_broker_services.map(&:id)) }

    context 'when there are no service instances' do
      let(:broker) { global_broker }
      let(:api_call) { lambda { |user_headers| delete "/v3/service_brokers/#{broker.guid}", nil, user_headers } }
      let(:db_check) {
        lambda do
          get "/v3/service_brokers/#{broker.guid}", {}, admin_headers
          expect(last_response.status).to eq(404)
        end
      }

      context 'global broker' do
        let(:broker) { global_broker }
        it_behaves_like 'permissions for delete endpoint', ALL_PERMISSIONS do
          let(:expected_codes_and_responses) {
            Hash.new(code: 404).tap do |h|
              h['admin'] = { code: 204 }
              h['admin_read_only'] = { code: 403 }
              h['global_auditor'] = { code: 403 }
            end
          }
        end
      end

      context 'space-scoped broker' do
        let(:broker) {  VCAP::CloudController::ServiceBroker.make(space_id: space.id) }

        it_behaves_like 'permissions for delete endpoint', ALL_PERMISSIONS do
          let(:expected_codes_and_responses) {
            Hash.new(code: 403).tap do |h|
              h['admin'] = { code: 204 }
              h['space_developer'] = { code: 204 }
              h['org_auditor'] = { code: 404 }
              h['org_billing_manager'] = { code: 404 }
              h['no_role'] = { code: 404 }
            end
          }
        end
      end

      context 'a successful delete' do
        before do
          VCAP::CloudController::Event.dataset.destroy
          delete "/v3/service_brokers/#{global_broker.guid}", {}, admin_headers
        end

        it 'deletes the UAA clients related to this broker' do
          uaa_client_id = "#{global_broker_id}-uaa-id"
          expect(VCAP::CloudController::ServiceDashboardClient.find_client_by_uaa_id(uaa_client_id)).to be_nil

          expect(a_request(:post, 'https://uaa.service.cf.internal/oauth/clients/tx/modify').
              with(
                body: [
                  {
                        "client_id": uaa_client_id,
                        "client_secret": nil,
                        "redirect_uri": nil,
                        "scope": %w(openid cloud_controller_service_permissions.read),
                        "authorities": ['uaa.resource'],
                        "authorized_grant_types": ['authorization_code'],
                        "action": 'delete'
                    }
                ].to_json
              )).to have_been_made
        end

        it 'emits service and plan deletion events, and broker deletion event' do
          expect([
            { type: 'audit.service.delete', actor: 'broker name' },
            { type: 'audit.service.delete', actor: 'broker name' },
            { type: 'audit.service_broker.delete', actor: admin_headers._generated_email },
            { type: 'audit.service_dashboard_client.delete', actor: 'broker name' },
            { type: 'audit.service_plan.delete', actor: 'broker name' },
            { type: 'audit.service_plan.delete', actor: 'broker name' }
          ]).to be_reported_as_events
        end

        it 'deletes the associated service offerings and plans' do
          services = VCAP::CloudController::Service.where(id: global_broker_services.map(&:id))
          expect(services).to have(0).items

          plans = VCAP::CloudController::ServicePlan.where(id: global_broker_plans.map(&:id))
          expect(plans).to have(0).items
        end
      end
    end

    context 'when the broker does not exist' do
      before do
        delete '/v3/service_brokers/guid-that-does-not-exist', {}, admin_headers
      end

      it 'responds with 404 Not Found' do
        expect(last_response).to have_status_code(404)

        response = parsed_response['errors'].first
        expect(response).to include('title' => 'CF-ResourceNotFound')
        expect(response).to include('detail' => 'Service broker not found')
      end
    end

    context 'when there are service instances' do
      before do
        create_service_instance(global_broker, with: admin_headers)
        delete "/v3/service_brokers/#{global_broker.guid}", {}, admin_headers
      end

      it 'responds with 422 Unprocessable entity' do
        expect(last_response).to have_status_code(422)

        response = parsed_response['errors'].first
        expect(response).to include('title' => 'CF-ServiceBrokerNotRemovable')
        expect(response).to include('detail' => "Can not remove brokers that have associated service instances: #{global_broker.name}")
      end

      def create_service_instance(broker, with:)
        service = VCAP::CloudController::Service.where(service_broker_id: broker.id).first
        plan = VCAP::CloudController::ServicePlan.where(service_id: service.id).first
        plan.public = true
        plan.save

        request_body = {
            name: 'my-service-instance',
            space_guid: space.guid,
            service_plan_guid: plan.guid
        }
        # TODO: replace this with v3 once it's implemented
        post('/v2/service_instances', request_body.to_json, with)
        expect(last_response).to have_status_code(201)
      end
    end
  end

  def create_broker(broker_body, with:)
    @count_before_creation = VCAP::CloudController::ServiceBroker.count
    post('/v3/service_brokers', broker_body.to_json, with)
  end

  def create_broker_successfully(broker_body, with:, execute_all_jobs: false)
    create_broker(broker_body, with: with)
    expect(last_response).to have_status_code(202)
    broker = VCAP::CloudController::ServiceBroker.last

    execute_all_jobs(expected_successes: 1, expected_failures: 0) if execute_all_jobs

    broker
  end

  def expect_error(status:, error: '', description: '')
    expect(last_response).to have_status_code(status)
    expect(last_response.body).to include(error)
    expect(last_response.body).to include(description)
  end

  def stub_uaa_for(broker_id)
    stub_request(:get, "https://uaa.service.cf.internal/oauth/clients/#{broker_id}-uaa-id").
      to_return(
        { status: 404, body: {}.to_json, headers: { 'Content-Type' => 'application/json' } },
            { status: 200, body: { client_id: dashboard_client(broker_id)['id'] }.to_json, headers: { 'Content-Type' => 'application/json' } }
        )

    stub_request(:post, 'https://uaa.service.cf.internal/oauth/clients/tx/modify').
      with(
        body: [
          {
                "client_id": "#{broker_id}-uaa-id",
                "client_secret": 'my-dashboard-secret',
                "redirect_uri": 'http://example.org',
                "scope": %w(openid cloud_controller_service_permissions.read),
                "authorities": ['uaa.resource'],
                "authorized_grant_types": ['authorization_code'],
                "action": 'add'
            }
        ].to_json
        ).
      to_return(status: 201, body: {}.to_json, headers: { 'Content-Type' => 'application/json' })

    stub_request(:post, 'https://uaa.service.cf.internal/oauth/clients/tx/modify').
      with(
        body: [
          {
                "client_id": "#{broker_id}-uaa-id",
                "client_secret": nil,
                "redirect_uri": nil,
                "scope": %w(openid cloud_controller_service_permissions.read),
                "authorities": ['uaa.resource'],
                "authorized_grant_types": ['authorization_code'],
                "action": 'delete'
            }
        ].to_json
        ).
      to_return(status: 200, body: {}.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def catalog(id=global_broker_id)
    {
        'services' => [
          {
              'id' => "#{id}-1",
              'name' => 'service_name-1',
              'description' => 'some description 1',
              'bindable' => true,
              'plans' => [
                {
                      'id' => 'fake_plan_id-1',
                      'name' => 'plan_name-1',
                      'description' => 'fake_plan_description 1',
                      'schemas' => nil
                  }
              ],
              'dashboard_client' => dashboard_client(id)
          },
          {
              'id' => "#{id}-2",
              'name' => 'route_volume_service_name-2',
              'requires' => ['volume_mount', 'route_forwarding'],
              'description' => 'some description 2',
              'bindable' => true,
              'plans' => [
                {
                    'id' => 'fake_plan_id-2',
                    'name' => 'plan_name-2',
                    'description' => 'fake_plan_description 2',
                    'schemas' => nil
                }
              ]
          },
        ]
    }
  end

  def dashboard_client(id=global_broker_id)
    {
        'id' => "#{id}-uaa-id",
        'secret' => 'my-dashboard-secret',
        'redirect_uri' => 'http://example.org'
    }
  end
end
