require 'actions/services/service_key_delete'
require 'actions/services/route_binding_delete'
require 'actions/services/locks/deleter_lock'
require 'actions/service_instance_unshare'
require 'racecar/racecar'

module VCAP::CloudController
  class ServiceInstanceDelete
    def initialize(accepts_incomplete: false, event_repository:, racecar: Racecar::NONE)
      @accepts_incomplete = accepts_incomplete
      @event_repository = event_repository
      @racecar = racecar
    end

    def delete(service_instance_dataset)
      service_instance_dataset.each_with_object([[], []]) do |service_instance, errors_and_warnings|
        @racecar.drive('service_instance_dataset[i]')
        errors_accumulator, warnings_accumulator = errors_and_warnings

        if service_instance.operation_in_progress?
          if service_instance.last_operation.type == 'create'
            delete_one_ignoring_pending_provision(service_instance)
          end

          errors_accumulator << CloudController::Errors::ApiError.new_from_details('AsyncServiceInstanceOperationInProgress', service_instance.name)
          next
        end

        errors, warnings = delete_service_bindings(service_instance)

        errors.concat unshare_from_all_spaces(service_instance)

        errors.concat delete_service_keys(service_instance)
        errors.concat delete_route_bindings(service_instance)

        if errors.empty?
          instance_errors = delete_one(service_instance)
          errors_accumulator.concat(instance_errors)
        else
          errors_accumulator << recursive_delete_error(service_instance, errors)
        end

        warnings_accumulator.concat(warnings)
      end
    end

    def can_return_warnings?
      true
    end

    private

    def unshare_from_all_spaces(service_instance)
      errors = []

      if service_instance.exists?
        service_instance.reload
      end

      return errors unless service_instance.service_bindings.empty?
      return errors unless service_instance.shared?

      unshare = ServiceInstanceUnshare.new
      service_instance.shared_spaces.each do |target_space|
        begin
          unshare.unshare(service_instance, target_space, @event_repository.user_audit_info)
        rescue => e
          errors << e
        end
      end

      errors
    end

    def delete_one_ignoring_pending_provision(service_instance)
      client = VCAP::Services::ServiceClientProvider.provide({ instance: service_instance })
      @racecar.drive('service_broker_client.deprovision()')
      attributes_to_update = client.deprovision(
       service_instance,
       accepts_incomplete: false
      )

      @racecar.drive('service_instance.destroy')
      service_instance.destroy
      log_audit_event(service_instance)
    end

    def delete_one(service_instance)
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
          @event_repository.record_service_instance_event(:start_delete, service_instance, {})
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
      errors.reject! do |err|
        err.instance_of?(CloudController::Errors::ApiError) && err.name == 'AsyncServiceBindingOperationInProgress'
      end
      bindings_in_progress(service_instance).each do |service_binding|
        errors << StandardError.new(
          "An operation for the service binding between app #{service_binding.app.name} and service instance #{service_binding.service_instance.name} is in progress."
        )
      end

      [errors, warnings]
    end

    def bindings_in_progress(service_instance)
      service_instance.service_bindings_dataset.all.select(&:operation_in_progress?)
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
        nil,
        'delete',
      )
    end

    def log_audit_event(service_instance)
      event_method = service_instance.managed_instance? ? :record_service_instance_event : :record_user_provided_service_instance_event
      @event_repository.send(event_method, :delete, service_instance, {})
    end

    def recursive_delete_error(service_instance, errors)
      msg = errors.map { |error| "\t#{error.message}" }.join("\n\n")
      CloudController::Errors::ApiError.new_from_details('ServiceInstanceRecursiveDeleteFailed', service_instance.name, msg)
    end
  end
end
