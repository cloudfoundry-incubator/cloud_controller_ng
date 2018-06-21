module VCAP::CloudController
  module Jobs
    module Services
      class ServiceBindingStateFetch < VCAP::CloudController::Jobs::CCJob
        def initialize(service_binding_guid, user_info, request_attrs, type=:binding)
          @service_binding_guid = service_binding_guid
          @end_timestamp = Time.now + Config.config.get(:broker_client_max_async_poll_duration_minutes).minutes
          @user_audit_info = user_info
          @request_attrs = request_attrs
          @type = type
          update_polling_interval
        end

        def perform
          logger = Steno.logger('cc-background')

          # binding.pry
          binding_resource = if @type == :service_key
                               ServiceKey.first(guid: @service_binding_guid)
                             else
                               ServiceBinding.first(guid: @service_binding_guid)
                             end

          return if binding_resource.nil? # assume the binding has been purged

          client = VCAP::Services::ServiceClientProvider.provide(instance: binding_resource.service_instance)
          last_operation_result = client.fetch_service_binding_last_operation(binding_resource)

          if binding_resource.last_operation.type == 'create'
            create_result = process_create_operation(logger, binding_resource, last_operation_result)
            return if create_result[:finished]
          elsif binding_resource.last_operation.type == 'delete'
            delete_result = process_delete_operation(binding_resource, last_operation_result)
            return if delete_result[:finished]
          end

          retry_job unless binding_resource.terminal_state?
        rescue HttpResponseError, Sequel::Error, VCAP::Services::ServiceBrokers::V2::Errors::ServiceBrokerApiTimeout => e
          logger.error("There was an error while fetching the service binding operation state: #{e}")
          retry_job
        end

        def max_attempts
          1
        end

        private

        def process_create_operation(logger, binding_resource, last_operation_result)
          if state_succeeded?(last_operation_result)
            client = VCAP::Services::ServiceClientProvider.provide(instance: binding_resource.service_instance)

            begin
              binding_response = client.fetch_service_binding(binding_resource)
            rescue HttpResponseError, VCAP::Services::ServiceBrokers::V2::Errors::ServiceBrokerApiTimeout => e
              set_binding_failed_state(binding_resource, logger)
              logger.error("There was an error while fetching the service binding details: #{e}")
              return { finished: true }
            end

            if @type == :service_key
              binding_resource.update({ 'credentials' => binding_response[:credentials] })
            else
              binding_resource.update({
                'credentials'      => binding_response[:credentials],
                'syslog_drain_url' => binding_response[:syslog_drain_url],
                'volume_mounts' => binding_response[:volume_mounts],
              })
            end
            record_event(binding_resource, @request_attrs)
            binding_resource.last_operation.update(last_operation_result[:last_operation])
            return { finished: true }
          end

          binding_resource.last_operation.update(last_operation_result[:last_operation])
          { finished: false }
        end

        # TODO: rename service_binding to something more generic
        def process_delete_operation(service_binding, last_operation_result)
          if binding_gone(last_operation_result) || state_succeeded?(last_operation_result)
            service_binding.destroy
            record_event(service_binding, @request_attrs)
            return { finished: true }
          end

          service_binding.last_operation.update(last_operation_result[:last_operation])
          { finished: false }
        end

        def retry_job
          update_polling_interval
          if Time.now + @poll_interval > @end_timestamp
            ServiceBinding.first(guid: @service_binding_guid).last_operation.update(
              state: 'failed',
              description: 'Service Broker failed to bind within the required time.'
            )
          else
            enqueue_again
          end
        end

        def record_event(binding, request_attrs)
          repository = Repositories::ServiceBindingEventRepository
          operation_type = binding.last_operation.type

          if operation_type == 'create'
            repository.record_create(binding, @user_audit_info, request_attrs)
          elsif operation_type == 'delete'
            repository.record_delete(binding, @user_audit_info)
          end
        end

        def enqueue_again
          opts = { queue: 'cc-generic', run_at: Delayed::Job.db_time_now + @poll_interval }
          Jobs::Enqueuer.new(self, opts).enqueue
        end

        def update_polling_interval
          @poll_interval = Config.config.get(:broker_client_default_async_poll_interval_seconds)
        end

        def set_binding_failed_state(service_binding, logger)
          service_binding.last_operation.update(
            state: 'failed',
            description: 'A valid binding could not be fetched from the service broker.',
          )
          SynchronousOrphanMitigate.new(logger).attempt_unbind(service_binding)
        end

        def binding_gone(result_from_broker)
          result_from_broker.empty?
        end

        def state_succeeded?(last_operation_result)
          last_operation_result[:last_operation][:state] == 'succeeded'
        end
      end
    end
  end
end
