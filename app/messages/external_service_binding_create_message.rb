require 'messages/base_message'

module VCAP::CloudController
  class ExternalServiceBindingCreateMessage < BaseMessage
    register_allowed_keys [:appGuid, :serviceInstanceGuid]

    validates_with NoAdditionalKeysValidator
  end
end
