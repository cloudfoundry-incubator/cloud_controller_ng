require 'actions/services/locks/lock_check'

module VCAP::CloudController
  class ServiceKeyDelete
    include VCAP::CloudController::LockCheck

    def initialize(accepts_incomplete=false)
      @accepts_incomplete = accepts_incomplete
    end

    def delete(service_key_dataset)
      service_key_dataset.each_with_object([]) do |service_key, errs|
        errs.concat delete_service_key(service_key)
      end
    end

    private

    def delete_service_key(service_key)
      errors = []
      service_instance = service_key.service_instance
      client = VCAP::Services::ServiceClientProvider.provide(instance: service_instance)

      begin
        raise_if_instance_locked(service_instance)
        # FIXME do we need user_audit_info ?
        broker_response = client.unbind(service_key, nil, @accepts_incomplete)

        if broker_response[:async]
          service_key.save_with_new_operation({ type: 'delete', state: 'in progress', broker_provided_operation: broker_response[:operation] })
          # Fetch last operation and update the service key object
        else
          service_key.destroy
        end
      rescue => e
        errors << e
      end

      errors
    end
  end
end
