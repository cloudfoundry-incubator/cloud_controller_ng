require 'actions/services/service_key_delete'
require 'actions/services/route_binding_delete'
require 'actions/services/locks/deleter_lock'
require 'actions/service_instance_unshare'

module VCAP::CloudController
  class ServiceInstanceDelete
    class AsynchronousBindingOperationInProgress < StandardError; end

    def initialize(accepts_incomplete: false, event_repository:)
      @accepts_incomplete = accepts_incomplete
      @event_repository = event_repository
    end

    def delete(service_instance_dataset)
      service_instance_dataset.each_with_object([[], []]) do |service_instance, errors_and_warnings|
        errors_accumulator, warnings_accumulator = errors_and_warnings
        errors, warnings = delete_service_bindings(service_instance)

        errors.concat delete_service_keys(service_instance)
        errors.concat delete_route_bindings(service_instance)

        errors.concat unshare_from_all_spaces(service_instance)

        errors_accumulator.concat(errors)
        warnings_accumulator.concat(warnings)

        if errors.empty?
          instance_errors = delete_service_instance(service_instance)
          errors_accumulator.concat(instance_errors)
        end
      end
    end

    def can_return_warnings?
      true
    end

    private

    def unshare_from_all_spaces(service_instance)
      errors = []

      if service_instance.shared?
        unshare = ServiceInstanceUnshare.new
        service_instance.shared_spaces.each do |target_space|
          begin
            unshare.unshare(service_instance, target_space, @event_repository.user_audit_info)
          rescue => e
            errors << e
          end
        end
      end

      errors
    end

    def delete_service_instance(service_instance)
      errors = []

      if !service_instance.exists?
        return []
      end

      begin
        lock = DeleterLock.new(service_instance)
        lock.lock!

        client = VCAP::Services::ServiceClientProvider.provide({ instance: service_instance })

        attributes_to_update = client.deprovision(
          service_instance,
          accepts_incomplete: @accepts_incomplete
        )

        if attributes_to_update[:last_operation][:state] == 'succeeded'
          lock.unlock_and_destroy!
          log_audit_event(service_instance)
        else
          lock.enqueue_unlock!(attributes_to_update, build_fetch_job(service_instance))
        end
      rescue => e
        errors << e
      ensure
        lock.unlock_and_fail! if lock.needs_unlock?
      end

      errors
    end

    def delete_route_bindings(service_instance)
      route_bindings_dataset = RouteBinding.where(service_instance_id: service_instance.id)
      route_deleter = RouteBindingDelete.new
      route_deleter.delete(route_bindings_dataset)
    end

    def delete_service_bindings(service_instance)
      service_binding_deleter = ServiceBindingDelete.new(@event_repository.user_audit_info, @accepts_incomplete)
      errors, warnings = service_binding_deleter.delete(service_instance.service_bindings)
      async_unbinds = service_instance.service_bindings_dataset.all.select(&:operation_in_progress?)

      if async_unbinds.any?
        errors << AsynchronousBindingOperationInProgress.new
      end

      [errors, warnings]
    end

    def delete_service_keys(service_instance)
      service_key_deleter = ServiceKeyDelete.new
      service_key_deleter.delete(service_instance.service_keys_dataset)
    end

    def build_fetch_job(service_instance)
      VCAP::CloudController::Jobs::Services::ServiceInstanceStateFetch.new(
        'service-instance-state-fetch',
        service_instance.guid,
        @event_repository.user_audit_info,
        {},
      )
    end

    def log_audit_event(service_instance)
      event_method = service_instance.managed_instance? ? :record_service_instance_event : :record_user_provided_service_instance_event
      @event_repository.send(event_method, :delete, service_instance, {})
    end
  end
end
