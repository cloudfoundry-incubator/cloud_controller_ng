require 'actions/services/locks/lock_check'

module VCAP::CloudController
  class ServiceKeyDelete
    include VCAP::CloudController::LockCheck

    def initialize(accepts_incomplete=false)
      @accepts_incomplete = accepts_incomplete
    end

    def delete(service_keys)
      service_keys_to_delete = Array(service_keys)
      errors = []
      warnings = []
      service_keys_to_delete.each do |service_key|
        result = delete_service_key(service_key)
        errors.concat result.first
        warnings.concat result.last
      end
      [errors, warnings]
    end

    def can_return_warnings?
      true
    end

    private

    def broker_responded_async_for_accepts_incomplete_false?(broker_response)
      broker_response[:async] && !@accepts_incomplete
    end

    def delete_service_key(service_key)
      errors = []
      warnings_accumulator = []
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

        if broker_responded_async_for_accepts_incomplete_false?(broker_response)
          warnings_accumulator << ['The service broker responded asynchronously to the unbind request, but the accepts_incomplete query parameter was false or not given.',
                                   'The service key may not have been successfully deleted on the service broker.'].join(' ')
        end
      rescue => e
        errors << e
      end

      [errors, warnings_accumulator]
    end
  end
end
