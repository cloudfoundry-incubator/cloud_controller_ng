require 'spec_helper'
require 'actions/services/route_binding_delete'

module VCAP::CloudController
  RSpec.describe RouteBindingDelete do
    let(:guid_pattern) { '[[:alnum:]-]+' }
    subject(:route_binding_delete) { RouteBindingDelete.new }

    def broker_url(broker)
      base_broker_uri = URI.parse(broker.broker_url)
      base_broker_uri.user = broker.auth_username
      base_broker_uri.password = broker.auth_password
      base_broker_uri.to_s
    end

    def route_binding_url_regex(opts={})
      route_binding = opts[:route_binding]
      route_binding_guid = route_binding.try(:guid) || guid_pattern
      service_instance = opts[:service_instance] || route_binding.try(:service_instance)
      service_instance_guid = service_instance.try(:guid) || guid_pattern
      broker = opts[:service_broker] || service_instance.service_plan.service.service_broker
      %r{#{broker_url(broker)}/v2/service_instances/#{service_instance_guid}/service_bindings/#{route_binding_guid}}
    end

    describe '#delete' do
      let!(:route_binding_1) { ServiceKey.make }
      let!(:route_binding_2) { ServiceKey.make }
      let(:service_instance) { route_binding_1.service_instance }
      let!(:route_binding_dataset) { ServiceKey.dataset }
      let(:user) { User.make }
      let(:user_email) { 'user@example.com' }
      let(:client) { instance_double(VCAP::Services::ServiceBrokers::V2::Client) }

      before do
        allow(VCAP::Services::ServiceClientProvider).to receive(:provide).and_return(client)
        allow(client).to receive(:unbind).and_return({})
      end

      it 'deletes the service keys' do
        route_binding_delete.delete(route_binding_dataset)

        expect { route_binding_1.refresh }.to raise_error Sequel::Error, 'Record not found'
        expect { route_binding_2.refresh }.to raise_error Sequel::Error, 'Record not found'
      end

      it 'deletes the service key from broker side' do
        route_binding_delete.delete(route_binding_dataset)
        expect(client).to have_received(:unbind).with(route_binding_1)
        expect(client).to have_received(:unbind).with(route_binding_2)
      end

      it 'fails if the instance has another operation in progress' do
        service_instance.service_instance_operation = ServiceInstanceOperation.make state: 'in progress'
        errors = route_binding_delete.delete([route_binding_1])
        expect(errors.first).to be_instance_of CloudController::Errors::ApiError
      end

      context 'when one key deletion fails' do
        let(:route_binding_3) { ServiceKey.make }

        before do
          allow(client).to receive(:unbind).with(route_binding_1).and_return({})
          allow(client).to receive(:unbind).with(route_binding_2).and_raise('meow')
          allow(client).to receive(:unbind).with(route_binding_3).and_return({})
        end

        it 'deletes all other keys' do
          route_binding_delete.delete(route_binding_dataset)

          expect { route_binding_1.refresh }.to raise_error Sequel::Error, 'Record not found'
          expect { route_binding_2.refresh }.not_to raise_error
          expect { route_binding_3.refresh }.to raise_error Sequel::Error, 'Record not found'
        end

        it 'returns all of the errors caught' do
          errors = route_binding_delete.delete(route_binding_dataset)
          expect(errors[0].message).to eq('meow')
        end
      end
    end
  end
end
