require 'messages/base_message'
require 'utils/hash_utils'
require 'messages/message_nested_validations'

module VCAP::CloudController
  class ServiceBrokerCreateMessage < BaseMessage
    extend MessageNestedValidations

    register_allowed_keys [:name, :url, :credentials, :relationships]
    ALLOWED_CREDENTIAL_TYPES = ['basic'].freeze

    validates_with NoAdditionalKeysValidator

    validates :name, string: true
    validates :url, string: true

    validates :credentials, hash: true
    validates_inclusion_of :credentials_type, in: ALLOWED_CREDENTIAL_TYPES,
      message: "credentials.type must be one of #{ALLOWED_CREDENTIAL_TYPES}"
    validate :validate_credentials_data

    # validates :relationships, hash: true, allow_nil: true
    # validate :validate_space_guid

    validates_nested :relationships, :space, :data, :guid, string: true

    # validates_nested :relationships do
    #   validates_nested :space, allow_nil: true do
    #     validates_nested :data do
    #       validates_nested :guid, string: true
    #       validates_nested :other_guid, string: true
    #     end
    #   end
    #
    #   validates_nested :org do
    #     validates_nested :data do
    #       validates_nested :guid, string: true
    #       validates_nested :other_guid, string: true
    #     end
    #   end
    # end

    def credentials_type
      HashUtils.dig(credentials, :type)
    end

    def credentials_data
      @credentials_data ||= BasicCredentialsMessage.new(HashUtils.dig(credentials, :data))
    end

    def validate_credentials_data
      unless credentials_data.valid?
        errors.add(
          :credentials_data,
          "Field(s) #{credentials_data.errors.keys.map(&:to_s)} must be valid: #{credentials_data.errors.full_messages}"
        )
      end
    end

    # def validate_space_guid
    #   if relationships.is_a?(Hash)
    #     unless relationships&.dig(:space).is_a?(Hash)
    #       errors.add(:relationships, 'relationships must contain relationships.space')
    #     end
    #   end
    # end

    class BasicCredentialsMessage < BaseMessage
      register_allowed_keys [:username, :password]

      validates_with NoAdditionalKeysValidator

      validates :username, string: true
      validates :password, string: true
    end
  end
end
