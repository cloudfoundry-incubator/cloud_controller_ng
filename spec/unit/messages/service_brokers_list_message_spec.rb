require 'spec_helper'
require 'messages/service_brokers_list_message'

module VCAP::CloudController
  RSpec.describe ServiceBrokersListMessage do
    describe '.from_params' do
      let(:params) do
        {
          'page'      => 1,
          'per_page'  => 5,
          'order_by'  => 'created_at',
          'space_guids' => 'space-guid-1,space-guid-2,space-guid-3'
        }
      end

      it 'returns the correct ServiceBrokersListMessage' do
        message = ServiceBrokersListMessage.from_params(params)

        expect(message).to be_a(ServiceBrokersListMessage)
        expect(message.page).to eq(1)
        expect(message.per_page).to eq(5)
        expect(message.order_by).to eq('created_at')
        expect(message.space_guids).to eq(['space-guid-1', 'space-guid-2', 'space-guid-3'])
      end

      it 'converts requested keys to symbols' do
        message = ServiceBrokersListMessage.from_params(params)

        expect(message.requested?(:page)).to be_truthy
        expect(message.requested?(:per_page)).to be_truthy
        expect(message.requested?(:order_by)).to be_truthy
        expect(message.requested?(:space_guids)).to be_truthy
      end
    end

    describe 'fields' do
      it 'accepts a set of fields' do
        message = ServiceBrokersListMessage.new({
            page: 1,
            per_page: 5,
            order_by: 'created_at',
            space_guids: ['space-guid-1', 'space-guid2']
          })
        expect(message).to be_valid
      end

      it 'accepts an empty set' do
        message = ServiceBrokersListMessage.new
        expect(message).to be_valid
      end

      it 'does not accept a field not in this set' do
        message = ServiceBrokersListMessage.new({ foobar: 'pants' })

        expect(message).not_to be_valid
        expect(message.errors[:base]).to include("Unknown query parameter(s): 'foobar'")
      end

      it 'does not accept non-array values for space_guids' do
        message = ServiceBrokersListMessage.new({
            space_guids: 'not-an-array'
          })
        expect(message).not_to be_valid
        expect(message.errors.first).to(eq([:space_guids, 'must be an array']))
      end
    end
  end
end
