require 'messages/base_message'

module VCAP::CloudController
  class ExternalServiceInstanceCreateMessage < BaseMessage
    register_allowed_keys [:plan, :service, :name]

    validates_with NoAdditionalKeysValidator
  end
end
