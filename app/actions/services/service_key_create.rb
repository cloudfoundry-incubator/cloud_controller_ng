require 'actions/services/synchronous_orphan_mitigate'
require 'actions/services/locks/lock_check'

module VCAP::CloudController
  class ServiceKeyCreate
    include VCAP::CloudController::LockCheck
    class InvalidServiceKey < StandardError; end
    class ServiceBrokerInvalidServiceKeyRetrievable < StandardError; end

    def initialize(logger)
      @logger = logger
    end

    def create(service_instance, key_attrs, arbitrary_parameters, accepts_incomplete)
      errors = []

      begin
        raise_if_instance_locked(service_instance)

        service_key = ServiceKey.new(key_attrs)

        client = VCAP::Services::ServiceClientProvider.provide(instance: service_instance)
        service_key_result = client.create_service_key(service_key, arbitrary_parameters: arbitrary_parameters, accepts_incomplete: accepts_incomplete)

        begin
          service_key.set(service_key_result[:service_key])
          if service_key_result[:async]
            raise ServiceBrokerInvalidServiceKeyRetrievable.new unless service_key.service.bindings_retrievable
            service_key.save_with_new_operation({ type: 'create', state: 'in progress', broker_provided_operation: service_key_result[:operation] })

            job = VCAP::CloudController::Jobs::Services::ServiceBindingStateFetch.new(service_key.guid, @user_audit_info, {}, :service_key)
            job.perform
            # enqueuer = Jobs::Enqueuer.new(job, queue: 'cc-generic')
            # enqueuer.enqueue
          end

          service_key.save
        rescue => e
          @logger.error "Failed to save state of create for service key #{service_key.guid} with exception: #{e}"
          orphan_mitigator = SynchronousOrphanMitigate.new(@logger)
          orphan_mitigator.attempt_delete_key(service_key)
          raise
        end
      rescue => e
        errors << e
      end

      [service_key, errors]
    end
  end
end
