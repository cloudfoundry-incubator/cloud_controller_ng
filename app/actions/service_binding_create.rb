require 'actions/services/synchronous_orphan_mitigate'
require 'actions/services/locks/lock_check'
require 'repositories/service_binding_event_repository'
require 'jobs/services/service_binding_state_fetch'

module VCAP::CloudController
  class ServiceBindingCreate
    class InvalidServiceBinding < StandardError; end
    class ServiceInstanceNotBindable < InvalidServiceBinding; end
    class ServiceBrokerInvalidSyslogDrainUrl < InvalidServiceBinding; end
    class ServiceBrokerInvalidBindingsRetrievable < InvalidServiceBinding; end
    class VolumeMountServiceDisabled < InvalidServiceBinding; end
    class SpaceMismatch < InvalidServiceBinding; end

    include VCAP::CloudController::LockCheck

    def initialize(user_audit_info)
      @user_audit_info = user_audit_info
    end

    def create(resource, service_instance, message, volume_mount_services_enabled, accepts_incomplete)
      raise ServiceInstanceNotBindable unless service_instance.bindable?
      raise VolumeMountServiceDisabled if service_instance.volume_service? && !volume_mount_services_enabled
      raise SpaceMismatch unless bindable_in_space?(service_instance, resource.space)
      raise_if_instance_locked(service_instance)
      # binding.pry
      if resource.host
        binding = RouteBinding.new
        binding.route = resource
        binding.service_instance = service_instance
      else
        binding = ServiceBinding.new(
          service_instance: service_instance,
          app:              resource,
          credentials:      {},
          type:             message.type,
          name:             message.name,
        )
      end

      raise InvalidServiceBinding.new(binding.errors.full_messages.join(' ')) unless binding.valid?

      client = VCAP::Services::ServiceClientProvider.provide(instance: service_instance)

      binding_result = request_binding_from_broker(client, binding, message.parameters, accepts_incomplete)

      if resource.host
        # this lookup might be wrong, we want to fetch just the route_service_url
        attributes_to_update = {
          route_service_url: binding_result[:route_service_url]
        }
        binding.set(attributes_to_update)
      else
        binding.set(binding_result[:binding])
      end

      begin
        if binding_result[:async]
          raise ServiceBrokerInvalidBindingsRetrievable.new unless binding.service.bindings_retrievable

          binding.save_with_new_operation({ type: 'create', state: 'in progress', broker_provided_operation: binding_result[:operation] })
          job = Jobs::Services::ServiceBindingStateFetch.new(binding.guid, @user_audit_info, message.audit_hash)
          enqueuer = Jobs::Enqueuer.new(job, queue: 'cc-generic')
          enqueuer.enqueue
        else
          if resource.host
            services_event_repository.record_service_instance_event(:bind_route, binding.service_instance, { route_guid: binding.guid })
          else
            binding.save
            Repositories::ServiceBindingEventRepository.record_create(binding, @user_audit_info, message.audit_hash)
          end
        end
      rescue => e
        logger.error "Failed to save state of create for service binding #{binding.guid} with exception: #{e}"
        mitigate_orphan(binding)
        raise e
      end

      if resource.host
        binding.notify_diego
      end

      binding
    end

    private

    def services_event_repository
      ::CloudController::DependencyLocator.instance.services_event_repository
    end

    def request_binding_from_broker(client, service_binding, parameters, accepts_incomplete)
      client.bind(service_binding, parameters, accepts_incomplete).tap do |response|
        #why do this?
        # response.delete(:route_service_ur)
        response
      end
    end

    def mitigate_orphan(binding)
      orphan_mitigator = SynchronousOrphanMitigate.new(logger)
      orphan_mitigator.attempt_unbind(binding)
    end

    def bindable_in_space?(service_instance, app_space)
      service_instance.space == app_space || service_instance.shared_spaces.include?(app_space)
    end

    def logger
      @logger ||= Steno.logger('cc.action.service_binding_create')
    end
  end
end
