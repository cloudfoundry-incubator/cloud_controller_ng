require 'spec_helper'

module VCAP::CloudController
  RSpec.describe ServiceKeyManager do
    let(:guid_pattern) { '[[:alnum:]-]+' }
    let(:services_event_repository) { double :services_event_respository, record_service_key_event: nil }

    subject { ServiceKeyManager.new(services_event_repository, nil, nil) }

    def broker_url(broker)
      broker.broker_url
    end

    def stub_requests(broker)
      stub_request(:delete, %r{#{broker_url(broker)}/v2/service_instances/#{guid_pattern}/service_bindings/#{guid_pattern}}).
        with(basic_auth: basic_auth(service_broker: broker)).
        to_return(status: unbind_status, body: unbind_body.to_json)
    end

    #TODO: Add create context with pertinents expectations

    context '#delete' do
      let(:service_key) { ServiceKey.make }
      let(:unbind_status) { 200 }
      let(:unbind_body) { {} }

      let(:service_key_delete_action) { double(:service_key_delete_action) }
      let(:delete_action_job) { double(:delete_action_job) }

      before do
        stub_requests(service_key.service_instance.service.service_broker)
      end

      it 'use the delete action to delete the key' do
        expect(VCAP::CloudController::ServiceKeyDelete).to receive(:new).and_return(service_key_delete_action)
        expect(VCAP::CloudController::Jobs::DeleteActionJob).to receive(:new).with(ServiceKey, service_key.guid, service_key_delete_action).and_return(delete_action_job)
        expect(delete_action_job).to receive(:perform)

        subject.delete_service_key(service_key)
      end

      context 'locking the service instance' do
        context 'when the instance does not have a last_operation' do
          before do
            service_key.service_instance.service_instance_operation = nil
            service_key.service_instance.save
          end

          it 'still does not have last_operation after delete of its key' do
            service_instance = service_key.service_instance

            subject.delete_service_key(service_key)
            expect(service_instance.refresh.last_operation).to be_nil
          end
        end

        context 'when the instance has a last_operation' do
          before do
            service_key.service_instance.service_instance_operation = ServiceInstanceOperation.make(type: 'create', state: 'succeeded')
            service_key.service_instance.save
          end

          it 'maintains the last_operation state and type' do
            service_instance = service_key.service_instance

            subject.delete_service_key(service_key)
            expect(service_instance.refresh.last_operation.state).to eq 'succeeded'
            expect(service_instance.refresh.last_operation.type).to eq 'create'
          end

          context 'when the instance operation is in progress' do
            let(:last_operation) { ServiceInstanceOperation.make(state: 'in progress') }
            let(:instance) { ManagedServiceInstance.make }
            let(:service_key) { ServiceKey.make(service_instance: instance) }
            before do
              instance.service_instance_operation = last_operation
              instance.save
            end

            it 'should raise an error for unbind operation' do
              expect {
                subject.delete_service_key(service_key)
              }.to raise_error(CloudController::Errors::ApiError, "An operation for service instance #{instance.name} is in progress.")
              expect(ServiceKey.find(guid: service_key.guid)).not_to be_nil
            end
          end
        end
      end
    end
  end
end
