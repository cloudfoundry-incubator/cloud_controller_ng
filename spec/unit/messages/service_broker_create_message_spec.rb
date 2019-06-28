require 'lightweight_spec_helper'
require 'active_model'
require 'rspec/collection_matchers'
require 'messages/service_broker_create_message'

module VCAP::CloudController
  RSpec.describe ServiceBrokerCreateMessage do
    subject { ServiceBrokerCreateMessage }

    describe 'validations' do
      let(:valid_body) do
        {
          name: 'best-broker',
          url: 'the-best-broker.url',
          credentials: {
            type: 'basic',
            data: {
              username: 'user',
              password: 'pass',
            }
          },
        }
      end

      context 'when all values are correct' do
        let(:request_body) { valid_body }

        it 'is valid' do
          message = ServiceBrokerCreateMessage.new(request_body)
          expect(message).to be_valid
        end
      end

      context 'when unexpected keys are requested' do
        let(:request_body) do
          valid_body.merge(surprise_key: 'boo')
        end

        it 'is not valid' do
          message = ServiceBrokerCreateMessage.new(request_body)

          expect(message).not_to be_valid
          expect(message.errors[:base]).to include("Unknown field(s): 'surprise_key'")
        end
      end

      context 'name' do
        context 'when name is not a string' do
          let(:request_body) do
            valid_body.merge(name: true)
          end

          it 'is not valid' do
            message = ServiceBrokerCreateMessage.new(request_body)

            expect(message).not_to be_valid
            expect(message.errors_on(:name)).to include('must be a string')
          end
        end
      end

      context 'url' do
        context 'when url is not a string' do
          let(:request_body) do
            valid_body.merge(url: true)
          end

          it 'is not valid' do
            message = ServiceBrokerCreateMessage.new(request_body)
            expect(message).not_to be_valid
            expect(message.errors_on(:url)).to include('must be a string')
          end
        end
      end

      context 'credentials' do
        context 'when credentials is not a hash' do
          let(:request_body) do
            valid_body.except(:credentials)
          end

          it 'is not valid' do
            message = ServiceBrokerCreateMessage.new(request_body)

            expect(message).not_to be_valid
            expect(message.errors_on(:credentials)).to include('must be a hash')
          end
        end

        context 'when credentials.type is invalid' do
          let(:request_body) do
            valid_body.merge(credentials: {
              type: 'oopsie'
            })
          end

          it 'is not valid' do
            message = ServiceBrokerCreateMessage.new(request_body)

            expect(message).not_to be_valid
            expect(message.errors_on(:credentials_type)).to include('credentials.type must be one of ["basic"]')
          end
        end

        context 'when username and password are missing from data' do
          let(:request_body) do
            valid_body.merge(credentials: {
              type: 'basic',
              data: {},
            })
          end

          it 'is not valid' do
            message = ServiceBrokerCreateMessage.new(request_body)

            expect(message).not_to be_valid
            expect(message.errors_on(:credentials_data)).to include(/Field\(s\) \["username", "password"\] must be valid/)
          end
        end
      end

      context 'space guid relationship' do
        subject { ServiceBrokerCreateMessage.new(request_body) }

        context 'when replationships is structured properly' do
          let(:request_body) { valid_body.merge(relationships: { space: { data: { guid: 'space-guid-here' } } }) }

          it 'is valid' do
            expect(subject).to be_valid
            expect(subject.space_guid).to eq('space-guid-here')
          end
        end

        context 'when relationships is not a hash' do
          let(:request_body) { valid_body.merge(relationships: 42) }

          it 'is not valid' do
            expect(subject).not_to be_valid
            expect(subject.errors_on(:relationships)).to include("'relationships' is not a hash")
          end
        end

        context 'when relationships does not have a valid structure' do
          let(:request_body) { valid_body.merge(relationships: { oopsie: 'not valid', other: 'invalid' }) }

          it 'is not valid' do
            expect(subject).not_to be_valid
            expect(subject.errors_on(:relationships)).to include("Unknown field(s): 'oopsie', 'other'")
            expect(subject.errors_on(:relationships)).to include("Space can't be blank")
            expect(subject.errors_on(:relationships)).to include('Space must be structured like this: "space: {"data": {"guid": "valid-guid"}}"')
          end
        end

        context 'when replationships.space is not a hash' do
          let(:request_body) { valid_body.merge(relationships: { space: 42 }) }

          it 'is not valid' do
            expect(subject).not_to be_valid
            expect(subject.errors_on(:relationships)).to include('Space must be structured like this: "space: {"data": {"guid": "valid-guid"}}"')
          end
        end

        context 'when relationships.space does not have a valid structure' do
          let(:request_body) { valid_body.merge(relationships: { space: { oopsie: 'not valid', other: 'invalid' } }) }

          it 'is not valid' do
            expect(subject).not_to be_valid
            expect(subject.errors_on(:relationships)).to include('Space must be structured like this: "space: {"data": {"guid": "valid-guid"}}"')
          end
        end

        context 'when replationships.space.data is not a hash' do
          let(:request_body) { valid_body.merge(relationships: { space: { data: 42 } }) }

          it 'is not valid' do
            expect(subject).not_to be_valid
            expect(subject.errors_on(:relationships)).to include('Space must be structured like this: "space: {"data": {"guid": "valid-guid"}}"')
          end
        end

        context 'when relationships.space.data does not have a valid structure' do
          let(:request_body) { valid_body.merge(relationships: { space: { data: { oopsie: 'not valid', other: 'invalid' } } }) }

          it 'is not valid' do
            expect(subject).not_to be_valid
            expect(subject.errors_on(:relationships)).to include('Space must be structured like this: "space: {"data": {"guid": "valid-guid"}}"')
          end
        end

        context 'when replationships.space.data.guid is not a string' do
          let(:request_body) { valid_body.merge(relationships: { space: { data: { guid: 42 } } }) }

          it 'is not valid' do
            expect(subject).not_to be_valid
            expect(subject.errors_on(:relationships)).to include('Space guid must be a string')
            expect(subject.errors_on(:relationships)).to include('Space guid must be between 1 and 200 characters')
          end
        end
      end
    end
  end
end
