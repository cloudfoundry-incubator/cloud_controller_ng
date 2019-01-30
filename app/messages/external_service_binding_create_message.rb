require 'messages/base_message'

module VCAP::CloudController
  class ExternalServiceBindingCreateMessage < BaseMessage
    register_allowed_keys [:app_guid, :service_instance_guid]

    validates_with NoAdditionalKeysValidator
  end
end
