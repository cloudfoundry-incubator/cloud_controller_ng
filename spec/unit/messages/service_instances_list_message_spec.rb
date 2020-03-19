require 'spec_helper'
require 'messages/service_instances_list_message'

module VCAP::CloudController
  RSpec.describe ServiceInstancesListMessage do
    describe '.from_params' do
      let(:params) do
        {
          'page'      => 1,
          'per_page'  => 5,
          'order_by'  => 'name',
          'names' => 'rabbitmq, redis,mysql',
          'space_guids' => 'space-1, space-2, space-3',
          'label_selector' => 'key=value',
          'type' => 'managed',
          'service_plan_names' => 'plan1, plan2',
          'service_plan_guids' => 'guid1, guid2',
          'fields' => {'space.organization' => 'name'},
        }.with_indifferent_access
      end

      it 'returns the correct ServiceInstancesListMessage' do
        message = ServiceInstancesListMessage.from_params(params)

        expect(message).to be_a(ServiceInstancesListMessage)
        expect(message).to be_valid
        expect(message.page).to eq(1)
        expect(message.per_page).to eq(5)
        expect(message.order_by).to eq('name')
        expect(message.names).to match_array(['mysql', 'rabbitmq', 'redis'])
        expect(message.space_guids).to match_array(['space-1', 'space-2', 'space-3'])
        expect(message.label_selector).to eq('key=value')
        expect(message.type).to eq('managed')
        expect(message.service_plan_guids).to match_array(['guid1', 'guid2'])
        expect(message.service_plan_names).to match_array(['plan1', 'plan2'])
        expect(message.fields).to match({:'space.organization' => 'name'})
      end

      it 'converts requested keys to symbols' do
        message = ServiceInstancesListMessage.from_params(params)

        expect(message.requested?(:page)).to be_truthy
        expect(message.requested?(:per_page)).to be_truthy
        expect(message.requested?(:order_by)).to be_truthy
        expect(message.requested?(:names)).to be_truthy
        expect(message.requested?(:space_guids)).to be_truthy
        expect(message.requested?(:label_selector)).to be_truthy
        expect(message.requested?(:type)).to be_truthy
        expect(message.requested?(:service_plan_guids)).to be_truthy
        expect(message.requested?(:service_plan_names)).to be_truthy
        expect(message.requested?(:fields)).to be_truthy
      end
    end

    describe 'validations' do
      it 'accepts an empty set' do
        message = ServiceInstancesListMessage.from_params({})
        expect(message).to be_valid
      end

      it 'does not accept a field not in this set' do
        message = ServiceInstancesListMessage.from_params({ foobar: 'pants' }.with_indifferent_access)

        expect(message).not_to be_valid
        expect(message.errors[:base][0]).to include("Unknown query parameter(s): 'foobar'")
      end

      it 'validates metadata requirements' do
        message = ServiceInstancesListMessage.from_params({ 'label_selector' => '' }.with_indifferent_access)

        expect_any_instance_of(Validators::LabelSelectorRequirementValidator).
          to receive(:validate).
          with(message).
          and_call_original
        message.valid?
      end

      it 'validates `fields`' do
        message = ServiceInstancesListMessage.from_params({'fields' => 'foo'}.with_indifferent_access)
        expect(message).not_to be_valid
        expect(message.errors[:fields][0]).to include("must be an object")
      end

      context 'type' do
        it 'allows `managed`' do
          message = ServiceInstancesListMessage.from_params({ type: 'managed' }.with_indifferent_access)
          expect(message).to be_valid
        end

        it 'allows `user-provided`' do
          message = ServiceInstancesListMessage.from_params({ type: 'managed' }.with_indifferent_access)
          expect(message).to be_valid
        end

        it 'does not allow other values' do
          message = ServiceInstancesListMessage.from_params({ type: 'magic' }.with_indifferent_access)
          expect(message).to be_invalid
          expect(message.errors[:type]).to include("must be one of 'managed', 'user-provided'")
        end
      end
    end
  end
end
