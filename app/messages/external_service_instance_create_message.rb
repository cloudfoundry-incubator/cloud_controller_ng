require 'messages/base_message'

module VCAP::CloudController
  class ExternalServiceInstanceCreateMessage < BaseMessage
    register_allowed_keys [:plan_id, :service_id, :name, :space_guid ]

    validates_with NoAdditionalKeysValidator
  end
end
