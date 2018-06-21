require 'spec_helper'
require 'actions/services/service_key_delete'

module VCAP::CloudController
  RSpec.describe ServiceKeyDelete do
    let(:guid_pattern) { '[[:alnum:]-]+' }
    subject(:service_key_delete) { ServiceKeyDelete.new(accepts_incomplete) }
    let(:accepts_incomplete) { false }

    def broker_url(broker)
      base_broker_uri = URI.parse(broker.broker_url)
      base_broker_uri.user = broker.auth_username
      base_broker_uri.password = broker.auth_password
      base_broker_uri.to_s
    end

    def service_key_url_regex(opts={})
      service_key = opts[:service_key]
      service_key_guid = service_key.try(:guid) || guid_pattern
      service_instance = opts[:service_instance] || service_key.try(:service_instance)
      service_instance_guid = service_instance.try(:guid) || guid_pattern
      broker = opts[:service_broker] || service_instance.service_plan.service.service_broker
      %r{#{broker_url(broker)}/v2/service_instances/#{service_instance_guid}/service_bindings/#{service_key_guid}}
    end


    describe '#delete' do
      let!(:service_key_1) { ServiceKey.make }
      let!(:service_key_2) { ServiceKey.make }
      let(:service_instance) { service_key_1.service_instance }
      let!(:service_key_dataset) { ServiceKey.dataset }
      let(:user) { User.make }
      let(:user_email) { 'user@example.com' }
      let(:client) { instance_double(VCAP::Services::ServiceBrokers::V2::Client) }

      before do
        allow(VCAP::Services::ServiceClientProvider).to receive(:provide).and_return(client)
        allow(client).to receive(:unbind).and_return({})
      end

      it 'deletes the service keys' do
        service_key_delete.delete(service_key_dataset)

        expect { service_key_1.refresh }.to raise_error Sequel::Error, 'Record not found'
        expect { service_key_2.refresh }.to raise_error Sequel::Error, 'Record not found'
      end

      it 'deletes single service key' do
        service_key_delete.delete(service_key_1)

        expect { service_key_1.refresh }.to raise_error Sequel::Error, 'Record not found'
      end

      it 'deletes the service key from broker side' do
        service_key_delete.delete(service_key_dataset)
        expect(client).to have_received(:unbind).with(service_key_1, nil, false)
        expect(client).to have_received(:unbind).with(service_key_2, nil, false)
      end

      it 'fails if the instance has another operation in progress' do
        service_instance.service_instance_operation = ServiceInstanceOperation.make state: 'in progress'
        errors, warnings = service_key_delete.delete([service_key_1])
        expect(errors.first).to be_instance_of CloudController::Errors::ApiError
        expect(errors.first.message).to eq("An operation for service instance #{service_instance.name} is in progress.")
        expect(warnings).to be_empty
      end

      context 'when one key deletion fails' do
        let(:service_key_3) { ServiceKey.make }

        before do
          allow(client).to receive(:unbind).with(service_key_1, nil, false).and_return({})
          allow(client).to receive(:unbind).with(service_key_2, nil, false).and_raise('meow')
          allow(client).to receive(:unbind).with(service_key_3, nil, false).and_return({})
        end

        it 'deletes all other keys' do
          service_key_delete.delete(service_key_dataset)

          expect { service_key_1.refresh }.to raise_error Sequel::Error, 'Record not found'
          expect { service_key_2.refresh }.not_to raise_error
          expect { service_key_3.refresh }.to raise_error Sequel::Error, 'Record not found'
        end

        it 'returns all of the errors caught' do
          errors, warnings = service_key_delete.delete(service_key_dataset)
          expect(errors[0].message).to eq('meow')
          expect(warnings).to be_empty
        end
      end

      context 'when accepts_incomplete is true' do
        let(:service_key_delete) { ServiceKeyDelete.new(true) }

        context 'when the broker responds asynchronously' do
          let(:service_key_operation) { ServiceKeyOperation.make }

          before do
            allow(client).to receive(:unbind).and_return({ async: true, operation: '123' })
          end

          it 'asks the broker to delete the service key async' do
            expect(client).to receive(:unbind).with(service_key_1, nil, true)
            service_key_delete.delete(service_key_dataset)
          end

          context 'when the service key does not already have an operation' do
            it 'updates the service key operation in the model' do
              service_key_delete.delete(service_key_dataset)
              service_key_2.reload

              expect(service_key_2.last_operation.type).to eql('delete')
              expect(service_key_2.last_operation.state).to eql('in progress')
            end

            it 'service key operation has broker provided operation' do
              service_key_delete.delete(service_key_dataset)
              service_key_1.reload

              expect(service_key_1.last_operation.broker_provided_operation).to eq('123')
            end
          end
        end
      end
      context 'when broker responds to accepts_incomplete flag' do
        let(:service_key) { ServiceKey.make }

        before do
          allow(VCAP::Services::ServiceClientProvider).to receive(:provide).and_return(client)
          allow(client).to receive(:unbind).and_return({})
        end

        context 'when accepts_incomplete is true' do
          let(:accepts_incomplete) { true }

          context 'when the broker responds synchronously' do
            before do
              allow(client).to receive(:unbind).and_return({ async: false })
            end

            it 'there should be no warnings or errors' do
              errors, warnings = service_key_delete.delete(service_key)
              expect(warnings).to be_empty
              expect(errors).to be_empty
            end
          end

          context 'when the broker responds asynchronously' do
            before do
              allow(client).to receive(:unbind).and_return({ async: true })
            end

            it 'there should be no warnings or errors' do
              errors, warnings = service_key_delete.delete(service_key)
              expect(warnings).to be_empty
              expect(errors).to be_empty
            end
          end
        end

        context 'when accepts_incomplete is false' do
          let(:accepts_incomplete) { false }

          context 'when the broker unexpectedly responds asynchronously' do
            let(:expected_warning) do
              ['The service broker responded asynchronously to the unbind request, but the accepts_incomplete query parameter was false or not given.',
               'The service key may not have been successfully deleted on the service broker.'].join(' ')
            end

            before do
              allow(client).to receive(:unbind).and_return({ async: true })
            end

            it 'should say that the broker responded poorly' do
              errors, warnings = service_key_delete.delete(service_key)
              expect(warnings).to match_array([expected_warning])
              expect(errors).to be_empty
            end

            context 'when delete is called with multiple bindings' do
              it 'should return warnings for both bindings' do
                errors, warnings = service_key_delete.delete([service_key, ServiceKey.make])
                expect(warnings).to match_array([expected_warning, expected_warning])
                expect(errors).to be_empty
              end
            end
          end

          context 'when the broker responded synchronously' do
            before do
              allow(client).to receive(:unbind).and_return({ async: false })
            end

            it 'there should be no warnings or errors' do
              errors, warnings = service_key_delete.delete(service_key)
              expect(warnings).to be_empty
              expect(errors).to be_empty
            end
          end
        end
      end
    end


    describe '#can_return_warnings?' do
      it 'returns true' do
        expect(service_key_delete.can_return_warnings?).to be true
      end
    end
  end
end
