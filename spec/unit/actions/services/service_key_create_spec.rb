require 'spec_helper'
require 'actions/services/service_key_create'

module VCAP::CloudController
  RSpec.describe ServiceKeyCreate do
    subject(:service_key_create) { ServiceKeyCreate.new(logger) }
    let(:service) { Service.make(bindings_retrievable: true) }
    let(:service_plan) { ServicePlan.make(service: service) }
    let(:service_instance) { ManagedServiceInstance.make(service_plan: service_plan) }
    let(:service_binding_url_pattern) { %r{/v2/service_instances/#{service_instance.guid}/service_bindings/} }
    let(:client) { instance_double(VCAP::Services::ServiceBrokers::V2::Client) }

    describe 'creating a service key' do
      let(:logger) { double(Steno::Logger) }
      let(:key_attrs) do
        {
          'name' => 'key-name',
          'service_instance_guid' => service_instance.guid,
        }
      end

      before do
        allow(VCAP::Services::ServiceClientProvider).to receive(:provide).
          and_return(client)
        allow(client).to receive(:create_service_key).and_return({ key: { credentials: { foo: 'bar' } } })

        allow(logger).to receive :error
        allow(logger).to receive :info
      end

      it 'successfully sets service key credentials' do
        service_key_create = ServiceKeyCreate.new(logger)
        key, errors = service_key_create.create(service_instance, key_attrs, {})
        expect(errors).to be_empty
        expect(key.credentials).to eq({ 'foo' => 'bar' })
      end

      context 'and the instance has another operation in progress' do
        it 'fails' do
          service_instance.service_instance_operation = ServiceInstanceOperation.make state: 'in progress'
          service_key_create = ServiceKeyCreate.new(logger)
          _, errors = service_key_create.create(service_instance, key_attrs, {})
          expect(errors.first).to be_instance_of CloudController::Errors::ApiError
        end
      end

      context 'when the broker returns an error on creation' do
        before do
          allow(client).to receive(:create_service_key).and_raise('meow')
        end

        it 'does not create a key' do
          ServiceKeyCreate.new(logger).create(service_instance, key_attrs, {})
          expect(ServiceKey.count).to eq 0
        end
      end

      context 'when broker request is successful but the database fails to save the key (hail mary)' do
        before do
          allow_any_instance_of(ServiceKey).to receive(:save).and_raise
        end

        it 'immediately attempts to delete the service key' do
          expect_any_instance_of(SynchronousOrphanMitigate).to receive(:attempt_delete_key)
          subject.create(service_instance, key_attrs, {})
        end

        it 'logs that the save failed' do
          allow_any_instance_of(SynchronousOrphanMitigate).to receive(:attempt_delete_key)
          subject.create(service_instance, key_attrs, {})
          expect(logger).to have_received(:error).with /Failed to save/
        end
      end

      context 'when accepts_incomplete=true' do
        let(:accepts_incomplete) { true }
        let(:arbitrary_parameters) { {} }

        context 'and the broker responds asynchronously' do
          before do
            allow(client).to receive(:create_service_key).and_return({ async: true, service_key: { credentials: { foo: 'bar' } }, operation: '123' })
          end

          it 'returns the service key operation' do
            service_key, errors = service_key_create.create(service_instance, key_attrs, arbitrary_parameters, accepts_incomplete)
            expect(ServiceKey.count).to eq(1)
            expect(ServiceKeyOperation.count).to eq(1)
            expect(service_key.last_operation.state).to eq('in progress')
          end

          it 'service key operation has broker provided operation' do
            service_key, errors = service_key_create.create(service_instance, key_attrs, arbitrary_parameters, accepts_incomplete)
            expect(service_key.last_operation.broker_provided_operation).to eq('123')
          end

          it 'service key operation has type create' do
            service_key, errors = service_key_create.create(service_instance, key_attrs, arbitrary_parameters, accepts_incomplete)
            expect(service_key.last_operation.type).to eq('create')
          end

          it 'does not audit a create service key event' do
            service_key, errors = service_key_create.create(service_instance, key_attrs, arbitrary_parameters, accepts_incomplete)
            expect(Event.count).to eq(0)
          end

          # it 'enqueues a fetch job' do
          #   expect {
          #     service_key_create.create(app, service_instance, message, volume_mount_services_enabled, accepts_incomplete)
          #   }.to change { Delayed::Job.count }.from(0).to(1)
          #
          #   expect(Delayed::Job.first).to be_a_fully_wrapped_job_of Jobs::Services::ServicekeyStateFetch
          #   expect(Delayed::Job.first.queue).to eq('cc-generic')
          # end
        end
      end
    end
  end
end
