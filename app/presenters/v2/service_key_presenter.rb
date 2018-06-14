module CloudController
  module Presenters
    module V2
      class ServiceKeyPresenter < DefaultPresenter
        extend PresenterProvider

        present_for_class 'VCAP::CloudController::ServiceKey'

        def entity_hash(controller, service_key, opts, depth, parents, orphans=nil)
          default_hash = super(controller, service_key, opts, depth, parents, orphans)
          default_hash.merge!({
            'credentials' => redact_creds_if_necessary(service_key),
            'last_operation' => {
              'type'        => service_key.last_operation.try(:type) || 'create',
              'state'       => service_key.last_operation.try(:state) || 'succeeded',
              'description' => service_key.last_operation.try(:description) || '',
              'updated_at'  => service_key.last_operation.try(:updated_at) || service_key.updated_at,
              'created_at'  => service_key.last_operation.try(:created_at) || service_key.created_at,
            },
            'service_key_parameters_url' => "/v2/service_keys/#{service_key.guid}/parameters",
          })
        end
      end
    end
  end
end
