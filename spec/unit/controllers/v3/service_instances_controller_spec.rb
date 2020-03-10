require 'rails_helper'
require 'permissions_spec_helper'

RSpec.describe ServiceInstancesV3Controller, type: :controller do
  let(:user) { set_current_user(VCAP::CloudController::User.make) }
  let(:space) { VCAP::CloudController::Space.make(guid: 'space-1-guid') }
  let!(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make(space: space, name: 'service-instance-1') }

  describe '#update' do
    let(:labels) do
      {
        fruit: 'pineapple',
        truck: 'mazda5'
      }
    end
    let(:annotations) do
      {
        potato: 'yellow',
        beet: 'golden',
      }
    end
    let(:update_message) do
      {
        metadata: {
          labels: {
            fruit: 'passionfruit'
          },
          annotations: {
            potato: 'purple'
          }
        }
      }
    end
    before do
      VCAP::CloudController::LabelsUpdate.update(service_instance, labels, VCAP::CloudController::ServiceInstanceLabelModel)
      VCAP::CloudController::AnnotationsUpdate.update(service_instance, annotations, VCAP::CloudController::ServiceInstanceAnnotationModel)
    end

    context 'when the user is an admin' do
      before do
        set_current_user_as_admin
      end

      it 'updates the service_instance' do
        patch :update, params: { guid: service_instance.guid }.merge(update_message), as: :json

        expect(response.status).to eq(200)
        expect(parsed_body['metadata']['labels']).to eq({ 'fruit' => 'passionfruit', 'truck' => 'mazda5' })
        expect(parsed_body['metadata']['annotations']).to eq({ 'potato' => 'purple', 'beet' => 'golden' })

        service_instance.reload
        expect(service_instance.labels.map { |label| { key: label.key_name, value: label.value } }).
          to match_array([{ key: 'fruit', value: 'passionfruit' }, { key: 'truck', value: 'mazda5' }])
        expect(service_instance.annotations.map { |a| { key: a.key, value: a.value } }).
          to match_array([{ key: 'potato', value: 'purple' }, { key: 'beet', value: 'golden' }])
      end

      context 'when a label is deleted' do
        let(:request_body) do
          {
            metadata: {
              labels: {
                fruit: nil
              }
            }
          }
        end

        it 'succeeds' do
          patch :update, params: { guid: service_instance.guid }.merge(request_body), as: :json

          expect(response.status).to eq(200)
          expect(parsed_body['metadata']['labels']).to eq({ 'truck' => 'mazda5' })

          service_instance.reload
          expect(service_instance.labels.map { |label| { key: label.key_name, value: label.value } }).to match_array([{ key: 'truck', value: 'mazda5' }])
        end
      end

      context 'when an empty request is sent' do
        let(:update_message) do
          {}
        end

        it 'succeeds but does not modify existing metadata' do
          patch :update, params: { guid: service_instance.guid }.merge(update_message), as: :json
          expect(response.status).to eq(200)
          service_instance.reload
          expect(parsed_body['guid']).to eq(service_instance.guid)
          expect(parsed_body['metadata']['labels']).to eq({ 'truck' => 'mazda5', 'fruit' => 'pineapple' })
          expect(parsed_body['metadata']['annotations']).to eq({ 'potato' => 'yellow', 'beet' => 'golden' })
        end
      end

      context 'when the message is invalid' do
        let!(:update_message) { { animals: 'Cows' } }

        it 'fails' do
          patch :update, params: { guid: service_instance.guid }.merge(update_message), as: :json
          expect(response.status).to eq(422)
        end
      end

      context 'when there is no such service_instance' do
        it 'fails' do
          patch :update, params: { guid: "Greg's missing service_instance" }.merge(update_message), as: :json

          expect(response.status).to eq(404)
        end
      end

      context 'when there is an invalid label' do
        let(:request_body) do
          {
            metadata: {
              labels: {
                'cloudfoundry.org/label': 'value'
              }
            }
          }
        end

        it 'displays an informative error' do
          patch :update, params: { guid: service_instance.guid }.merge(request_body), as: :json
          expect(response.status).to eq(422)
          expect(response).to have_error_message(/label [\w\s]+ error/)
        end
      end

      context 'when there is an invalid annotation' do
        let(:request_body) do
          {
            metadata: {
              annotations: {
                key: 'big' * 5000
              }
            }
          }
        end

        it 'displays an informative error' do
          patch :update, params: { guid: service_instance.guid }.merge(request_body), as: :json
          expect(response.status).to eq(422)
          expect(response).to have_error_message(/annotation [\w\s]+ error/)
        end
      end

      context 'when there are too many annotations' do
        let(:request_body) do
          {
            metadata: {
              annotations: {
                radish: 'daikon',
                potato: 'idaho'
              }
            }
          }
        end

        before do
          VCAP::CloudController::Config.config.set(:max_annotations_per_resource, 2)
        end

        it 'fails with a 422' do
          patch :update, params: { guid: service_instance.guid }.merge(request_body), as: :json
          expect(response.status).to eq(422)
          expect(response).to have_error_message(/exceed maximum of 2/)
        end
      end

      context 'when an annotation is deleted' do
        let(:request_body) do
          {
            metadata: {
              annotations: {
                potato: nil
              }
            }
          }
        end

        it 'succeeds' do
          patch :update, params: { guid: service_instance.guid }.merge(request_body), as: :json

          expect(response.status).to eq(200)
          expect(parsed_body['metadata']['annotations']).to eq({ 'beet' => 'golden' })

          service_instance.reload
          expect(service_instance.annotations.map { |a| { key: a.key, value: a.value } }).to match_array([{ key: 'beet', value: 'golden' }])
        end
      end
    end

    describe 'authorization' do
      let(:org) { space.organization }

      it_behaves_like 'permissions endpoint' do
        let(:roles_to_http_responses) do
          {
            'admin' => 200,
            'admin_read_only' => 403,
            'global_auditor' => 403,
            'space_developer' => 200,
            'space_manager' => 403,
            'space_auditor' => 403,
            'org_manager' => 403,
            'org_auditor' => 404,
            'org_billing_manager' => 404,
          }
        end
        let(:api_call) { lambda { patch :update, params: { guid: service_instance.guid }.merge(update_message), as: :json } }
      end
    end
  end

  describe '#relationships_shared_spaces' do
    let(:target_space) { VCAP::CloudController::Space.make(guid: 'target-space-guid') }

    before do
      service_instance.add_shared_space(target_space)
    end

    context 'permissions by role' do
      role_to_expected_http_response = {
        'admin'               => 200,
        'space_developer'     => 200,
        'admin_read_only'     => 200,
        'global_auditor'      => 200,
        'space_manager'       => 200,
        'space_auditor'       => 200,
        'org_manager'         => 200,
        'org_auditor'         => 404,
        'org_billing_manager' => 404,
      }.freeze

      role_to_expected_http_response.each do |role, expected_return_value|
        context "and #{role} in the target space" do
          it "returns #{expected_return_value}" do
            set_current_user_as_role(role: role, org: space.organization, space: space, user: user)

            get :relationships_shared_spaces, params: { service_instance_guid: service_instance.guid }

            expect(response.status).to eq(expected_return_value),
              "Expected #{expected_return_value}, but got #{response.status}. Response: #{response.body}"
            if expected_return_value == 200
              expect(parsed_body['data'][0]['guid']).to eq(target_space.guid)
              expect(parsed_body['links']['self']['href']).to match(%r{/v3/service_instances/#{service_instance.guid}/relationships/shared_spaces$})
            end
          end
        end
      end
    end

    context 'when invalid service instance guid is provided' do
      it 'returns a 404' do
        set_current_user_as_role(role: 'space_developer', org: space.organization, space: space, user: user)
        get :relationships_shared_spaces, params: { service_instance_guid: 'nonexistent-guid' }

        expect(response.status).to eq 404
      end
    end

    context 'when the user has read access to the target space, but not to the source space' do
      it 'returns a 404' do
        set_current_user_as_role(role: 'space_developer', org: target_space.organization, space: target_space, user: user)
        get :relationships_shared_spaces, params: { service_instance_guid: service_instance.guid }

        expect(response.status).to eq 404
      end
    end
  end

  describe '#share_service_instance' do
    let(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make }
    let(:target_space) { VCAP::CloudController::Space.make }
    let(:target_space2) { VCAP::CloudController::Space.make }
    let(:service_instance_sharing_enabled) { true }
    let(:source_space) { service_instance.space }

    let(:request_body) do
      {
        data: [
          { guid: target_space.guid }
        ]
      }
    end

    before do
      set_current_user_as_admin
      VCAP::CloudController::FeatureFlag.make(name: 'service_instance_sharing', enabled: service_instance_sharing_enabled, error_message: nil)
    end

    it 'calls the service instance share action' do
      action = instance_double(VCAP::CloudController::ServiceInstanceShare)
      allow(VCAP::CloudController::ServiceInstanceShare).to receive(:new).and_return(action)

      expect(action).to receive(:create).with(service_instance, [target_space], an_instance_of(VCAP::CloudController::UserAuditInfo))

      post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
    end

    it 'shares the service instance to multiple target spaces' do
      action = instance_double(VCAP::CloudController::ServiceInstanceShare)
      allow(VCAP::CloudController::ServiceInstanceShare).to receive(:new).and_return(action)
      expect(action).to receive(:create).with(service_instance, a_collection_containing_exactly(target_space, target_space2), an_instance_of(VCAP::CloudController::UserAuditInfo))

      request_body[:data] << { guid: target_space2.guid }

      post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
      expect(response.status).to eq 200
    end

    context 'when the service instance share action errors' do
      before do
        action = instance_double(VCAP::CloudController::ServiceInstanceShare)
        allow(VCAP::CloudController::ServiceInstanceShare).to receive(:new).and_return(action)

        expect(action).to receive(:create).and_raise('boom')
      end

      it 'returns the error to the user' do
        expect {
          post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        }.to raise_error('boom')
      end
    end

    context 'when the service_instance_sharing feature flag is disabled' do
      let(:service_instance_sharing_enabled) { false }

      it 'should return a 403 HTTP status code' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json

        expect(response.status).to eq(403)
        expect(response.body).to include('FeatureDisabled')
        expect(response.body).to include('service_instance_sharing')
      end
    end

    context 'when the service instance does not exist' do
      it 'returns a 404' do
        post :share_service_instance, params: { service_instance_guid: 'nonexistent-service-instance-guid' }.merge(request_body), as: :json
        expect(response.status).to eq 404
        expect(response.body).to include('Service instance not found')
      end
    end

    context 'when the service instance is user provided' do
      let(:service_instance) { VCAP::CloudController::UserProvidedServiceInstance.make }

      it 'returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
        expect(response.body).to include('User-provided services cannot be shared')
      end
    end

    context 'when the service instance plan is from a private space scoped broker' do
      let(:target_org) { VCAP::CloudController::Organization.make(name: 'target-org') }
      let(:target_space) { VCAP::CloudController::Space.make(name: 'target-space', organization: target_org) }
      let(:broker) { VCAP::CloudController::ServiceBroker.make(space: space) }
      let(:service) { VCAP::CloudController::Service.make(service_broker: broker, label: 'space-scoped-service') }
      let(:service_plan) { VCAP::CloudController::ServicePlan.make(service: service, name: 'my-plan') }
      let(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make(service_plan: service_plan) }

      it 'returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
        expect(response.body).to include('Access to service space-scoped-service and plan my-plan is not enabled in target-org/target-space')
      end
    end

    context 'when the service instance is a route service' do
      let(:service) { VCAP::CloudController::Service.make(:routing) }
      let(:service_plan) { VCAP::CloudController::ServicePlan.make(service: service) }
      let(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make(service_plan: service_plan) }

      it 'returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
        expect(response.body).to include('Route services cannot be shared')
      end
    end

    context 'when the target space has a service instance with the same name' do
      before do
        target_space.add_service_instance(VCAP::CloudController::ManagedServiceInstance.make(name: service_instance.name))
      end

      it 'returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
        expect(response.body).to include("A service instance called #{service_instance.name} already exists in #{target_space.name}")
      end
    end

    context 'when the service is not shareable' do
      let(:service) { VCAP::CloudController::Service.make(extra: { shareable: false }.to_json) }
      let(:service_plan) { VCAP::CloudController::ServicePlan.make(service: service) }
      let(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make(service_plan: service_plan) }

      it 'returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
        expect(response.body).to include("The #{service.label} service does not support service instance sharing.")
      end
    end

    context 'when the target space does not exist' do
      before do
        request_body[:data] = [{ guid: 'nonexistent-space-guid' }]
      end

      it 'returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
        expect(response.body).to include("Unable to share service instance #{service_instance.name} with spaces ['nonexistent-space-guid']. ")
        expect(response.body).to include('Ensure the spaces exist and that you have access to them.')
        expect(response.body).not_to include('Write permission is required in order to share a service instance with a space.')
      end
    end

    context 'when the user does not have read access to the target space' do
      before do
        set_current_user_as_role(role: 'space_developer', org: source_space.organization, space: source_space, user: user)
      end

      it 'returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
        expect(response.body).to include("Unable to share service instance #{service_instance.name} with spaces ['#{target_space.guid}']. ")
        expect(response.body).to include('Ensure the spaces exist and that you have access to them.')
        expect(response.body).not_to include('Write permission is required in order to share a service instance with a space.')
      end
    end

    context 'when multiple target spaces do not exist' do
      before do
        request_body[:data] = [
          { guid: 'nonexistent-space-guid' },
          { guid: 'nonexistent-space-guid2' },
          { guid: target_space.guid }
        ]
      end

      it 'does not share to any of the valid target spaces and returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
        expect(response.body).to include("Unable to share service instance #{service_instance.name} with spaces ['nonexistent-space-guid', 'nonexistent-space-guid2']. ")
        expect(response.body).to include('Ensure the spaces exist and that you have access to them.')
        expect(response.body).not_to include('Write permission is required in order to share a service instance with a space.')
      end
    end

    context 'when the user is a SpaceAuditor in the target space' do
      before do
        set_current_user_as_role(role: 'space_developer', org: source_space.organization, space: source_space, user: user)
        set_current_user_as_role(role: 'space_auditor', org: target_space.organization, space: target_space, user: user)
      end

      it 'returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
        expect(response.body).to include("Unable to share service instance #{service_instance.name} with spaces ['#{target_space.guid}']. ")
        expect(response.body).to include('Write permission is required in order to share a service instance with a space.')
        expect(response.body).not_to include('Ensure the spaces exist and that you have access to them.')
      end
    end

    context 'when some target spaces are unreadable and some are unwriteable' do
      before do
        set_current_user_as_role(role: 'space_developer', org: source_space.organization, space: source_space, user: user)
        set_current_user_as_role(role: 'space_auditor', org: target_space.organization, space: target_space, user: user)

        request_body[:data] = [
          { guid: 'nonexistent-space-guid' },
          { guid: target_space.guid }
        ]
      end

      it 'returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
        expect(response.body).to include(
          "Unable to share service instance #{service_instance.name} with spaces ['nonexistent-space-guid']. Ensure the spaces exist and that you have access to them.\\n" \
          "Unable to share service instance #{service_instance.name} with spaces ['#{target_space.guid}']. "\
          'Write permission is required in order to share a service instance with a space.'
        )
      end
    end

    context 'when the user is a SpaceAuditor in multiple target spaces' do
      let(:request_body) do
        {
          data: [
            { guid: target_space.guid },
            { guid: target_space2.guid }
          ]
        }
      end

      before do
        set_current_user_as_role(role: 'space_developer', org: source_space.organization, space: source_space, user: user)
        set_current_user_as_role(role: 'space_auditor', org: target_space.organization, space: target_space, user: user)
        set_current_user_as_role(role: 'space_auditor', org: target_space2.organization, space: target_space2, user: user)
      end

      it 'returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
        expect(response.body).to include(target_space.guid)
        expect(response.body).to include(target_space2.guid)
        expect(response.body).to include("Unable to share service instance #{service_instance.name} with spaces ")
        expect(response.body).to include('Write permission is required in order to share a service instance with a space.')
      end
    end

    context 'when the request is malformed' do
      let(:request_body) {
        {
          bork: 'some-name',
        }
      }

      it 'returns a 422' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 422
      end
    end

    context 'when the user has access to the service instance through a share' do
      before do
        service_instance.add_shared_space(target_space)
        set_current_user_as_role(role: 'space_developer', org: target_space.organization, space: target_space, user: user)

        outer_space = VCAP::CloudController::Space.make
        request_body[:data] = [{ guid: outer_space.guid }]
      end

      after do
        service_instance.remove_shared_space(target_space)
      end

      it 'cannot share the service instance into another target space' do
        post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json
        expect(response.status).to eq 403
      end
    end

    describe 'permissions by role' do
      context 'when the user is a space developer in the source space' do
        before do
          set_current_user_as_role(role: 'space_developer', org: source_space.organization, space: source_space, user: user)
        end

        role_to_expected_http_response = {
          'admin'               => 200,
          'space_developer'     => 200,
          'admin_read_only'     => 403,
          'global_auditor'      => 403,
          'space_manager'       => 422,
          'space_auditor'       => 422,
          'org_manager'         => 422,
          'org_auditor'         => 422,
          'org_billing_manager' => 422,
        }.freeze

        role_to_expected_http_response.each do |role, expected_return_value|
          context "and #{role} in the target space" do
            it "returns #{expected_return_value}" do
              set_current_user_as_role(role: role, org: target_space.organization, space: target_space, user: user)

              post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json

              expect(response.status).to eq(expected_return_value),
                "Expected role #{role} to get #{expected_return_value}, but got #{response.status}. Response: #{response.body}"
              if expected_return_value == 200
                expect(parsed_body['data'][0]['guid']).to eq(target_space.guid)
              end
            end
          end
        end
      end

      context 'when the user is a space developer in the target space' do
        before do
          set_current_user_as_role(role: 'space_developer', org: target_space.organization, space: target_space, user: user)
        end

        role_to_expected_http_response = {
          'admin'               => 200,
          'space_developer'     => 200,
          'admin_read_only'     => 403,
          'global_auditor'      => 403,
          'space_manager'       => 403,
          'space_auditor'       => 403,
          'org_manager'         => 403,
          'org_auditor'         => 404,
          'org_billing_manager' => 404,
        }.freeze

        role_to_expected_http_response.each do |role, expected_return_value|
          context "and #{role} in the source space" do
            it "returns #{expected_return_value}" do
              set_current_user_as_role(role: role, org: source_space.organization, space: source_space, user: user)

              post :share_service_instance, params: { service_instance_guid: service_instance.guid }.merge(request_body), as: :json

              expect(response.status).to eq(expected_return_value),
                "Expected #{expected_return_value}, but got #{response.status}. Response: #{response.body}"
              if expected_return_value == 200
                expect(parsed_body['data'][0]['guid']).to eq(target_space.guid)
              end
            end
          end
        end
      end
    end
  end

  describe '#unshare_service_instance' do
    let(:service_instance) { VCAP::CloudController::ManagedServiceInstance.make }
    let(:target_space) { VCAP::CloudController::Space.make }
    let(:source_space) { service_instance.space }

    before do
      set_current_user_as_admin

      service_instance.add_shared_space(target_space)
      service_instance.reload
    end

    it 'unshares the service instance from the target space' do
      delete :unshare_service_instance, params: { service_instance_guid: service_instance.guid, space_guid: target_space.guid }
      expect(response.status).to eq 204
      expect(service_instance.shared_spaces).to be_empty
    end

    context 'service instance does not exist' do
      it 'returns with 404' do
        delete :unshare_service_instance, params: { service_instance_guid: 'not a service instance guid', space_guid: target_space.guid }
        expect(response.status).to eq(404)
      end
    end

    context 'target space does not exist' do
      it 'returns 422' do
        delete :unshare_service_instance, params: { service_instance_guid: service_instance.guid, space_guid: 'non-existent-target-space-guid' }
        expect(response.status).to eq(422)
        error_message = 'Unable to unshare service instance from space non-existent-target-space-guid. '\
          'Ensure the space exists and the service instance has been shared to this space.'
        expect(response.body).to include(error_message)
      end
    end

    context 'an application in the target space is bound to the service instance' do
      let(:test_app) { VCAP::CloudController::AppModel.make(space: target_space, name: 'manatea') }
      let!(:service_binding) { VCAP::CloudController::ServiceBinding.make(service_instance: service_instance, app: test_app, credentials: { 'amelia' => 'apples' }) }

      context 'and the service broker successfully unbinds' do
        before do
          stub_unbind(service_binding, status: 200, accepts_incomplete: true)
        end

        it 'returns 204 and unbinds the app in the target space' do
          delete :unshare_service_instance, params: { service_instance_guid: service_instance.guid, space_guid: target_space.guid }
          expect(response.status).to eq(204)
          expect(test_app.service_bindings).to be_empty
        end
      end

      context 'and the service broker fails to unbind' do
        before do
          stub_unbind(service_binding, status: 500, accepts_incomplete: true)
        end

        it 'returns 502 and does not unshare the service' do
          delete :unshare_service_instance, params: { service_instance_guid: service_instance.guid, space_guid: target_space.guid }
          expect(response.status).to eq(502)
          expect(response.body).to include('ServiceInstanceUnshareFailed')
          expect(test_app.service_bindings).to_not be_empty
        end

        it 'returns an error with detailed message' do
          delete :unshare_service_instance, params: { service_instance_guid: service_instance.guid, space_guid: target_space.guid }
          expect(response.body).to include('The service broker returned an invalid response')
        end
      end

      context 'and the service broker responds asynchronously to unbinds' do
        before do
          stub_unbind(service_binding, status: 202, accepts_incomplete: true)
        end

        it 'returns an error with message that an operation is in progress' do
          delete :unshare_service_instance, params: { service_instance_guid: service_instance.guid, space_guid: target_space.guid }

          expect(response.status).to eq(502)
          expect(response.body).to include("The binding between an application and service instance #{service_instance.name}" \
                                           " in space #{target_space.name} is being deleted asynchronously.")
        end
      end
    end

    context 'when the user has access to the service instance through a share' do
      before do
        service_instance.add_shared_space(target_space)
        set_current_user_as_role(role: 'space_developer', org: target_space.organization, space: target_space, user: user)
      end

      it 'cannot unshare the service instance' do
        delete :unshare_service_instance, params: { service_instance_guid: service_instance.guid, space_guid: target_space.guid }
        expect(response.status).to eq 403
      end
    end

    describe 'permissions by role' do
      role_to_expected_http_response = {
        'admin'               => 204,
        'space_developer'     => 204,
        'admin_read_only'     => 403,
        'global_auditor'      => 403,
        'space_manager'       => 403,
        'space_auditor'       => 403,
        'org_manager'         => 403,
        'org_auditor'         => 404,
        'org_billing_manager' => 404,
      }.freeze

      role_to_expected_http_response.each do |role, expected_return_value|
        context "when the user is a #{role} in the source space" do
          it "returns #{expected_return_value}" do
            set_current_user_as_role(role: role, org: source_space.organization, space: source_space, user: user)

            delete :unshare_service_instance, params: { service_instance_guid: service_instance.guid, space_guid: target_space.guid }

            expect(response.status).to eq(expected_return_value),
              "Expected #{expected_return_value}, but got #{response.status}. Response: #{response.body}"
          end
        end
      end
    end

    context 'when trying to unshare a service instance that has not been shared' do
      let(:target_space2) { VCAP::CloudController::Space.make }

      it 'returns 422' do
        delete :unshare_service_instance, params: { service_instance_guid: service_instance.guid, space_guid: target_space2.guid }
        expect(response.status).to eq(422)
        error_message = "Unable to unshare service instance from space #{target_space2.guid}. "\
          'Ensure the space exists and the service instance has been shared to this space.'
        expect(response.body).to include(error_message)
      end
    end

    context 'when there are multiple shares' do
      let(:target_space2) { VCAP::CloudController::Space.make }

      before do
        service_instance.add_shared_space(target_space2)
        service_instance.reload
      end

      it 'only deletes the requested share' do
        delete :unshare_service_instance, params: { service_instance_guid: service_instance.guid, space_guid: target_space.guid }
        expect(response.status).to eq(204)
        expect(service_instance.shared_spaces).to contain_exactly(target_space2)
      end
    end
  end
end
