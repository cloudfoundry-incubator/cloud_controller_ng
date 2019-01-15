require 'open3'
require 'ism/client'

module VCAP::CloudController
  class ServiceBrokerMigrate
    def migrate(broker)

      # Loads all model elements

      # Lock things

      # create new resources with the same guids / attritubes.
      # how do we rollback if one of these fails?

      # CREATE external service broker
      create_broker(broker)
      # CREATE external service instances
      create_service_instances(broker)
      # CREATE external service bindings

      # DELETE service bindings
      # DELETE service instances
      destroy_service_instances(broker)

      # DELETE service broker
      broker.destroy
    end

    def create_broker(broker)
      ism_client.create_broker(broker)
    end

    def create_service_instances(broker)
      broker.services.each do |service|
        service.service_plans.each do |plan|
          plan.service_instances.each do |service_instance|
            migrate_service_instance(service_instance)
          end
        end
      end
    end

    def destroy_service_instances(broker)
      broker.services.each do |service|
        service.service_plans.each do |plan|
          plan.service_instances.each do |service_instance|
            destroy_service_instance(service_instance)
          end
        end
      end
    end

    def migrate_service_instance(service_instance)
      service_plan = service_instance.service_plan
      service = service_plan.service

      ism_client.migrate_service_instance(service_instance.guid, service_instance.name, service.unique_id, service_plan.unique_id)
    end

    def destroy_service_instance(service_instance)
      service_instance.destroy
    end

    def ism_client
      @ism_client ||= ISM::Client.new
    end
  end
end
