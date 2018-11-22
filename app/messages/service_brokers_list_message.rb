require 'messages/list_message'
require 'messages/validators/label_selector_requirement_validator'

module VCAP::CloudController
  class ServiceBrokersListMessage < ListMessage
    # register_allowed_keys [
    #   :names,
    #   :guids,
    #   :space_guids
    # ]
    #
    # validates_with NoAdditionalParamsValidator
    #
    # validates :space_guids, array: true, allow_nil: true

    def self.from_params(params)
      super(params, [])
      # super(params, %w(names guids space_guids))
    end
  end
end
