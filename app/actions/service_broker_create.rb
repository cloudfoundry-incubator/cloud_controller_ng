module VCAP::CloudController
  module V3
    class ServiceBrokerCreate
      class SpaceNotFound < StandardError; end

      def initialize(service_event_repository, service_manager)
        @service_event_repository = service_event_repository
        @service_manager = service_manager
      end

      def create(message)
        params = {
          name: message.name,
          broker_url: message.url,
          auth_username: message.credentials_data.username,
          auth_password: message.credentials_data.password,
        }

        if message.space_guid
          params[:space_id] = get_space_id_from_guid(message.space_guid)
        end

        broker = VCAP::CloudController::ServiceBroker.new(params)

        registration = VCAP::Services::ServiceBrokers::ServiceBrokerRegistration.new(
          broker,
          service_manager,
          service_event_repository,
          route_services_enabled?,
          volume_services_enabled?,
        )

        registration.create

        {
          warnings: registration.warnings
        }
      end

      private

      attr_reader :service_event_repository, :service_manager

      def route_services_enabled?
        VCAP::CloudController::Config.config.get(:route_services_enabled)
      end

      def volume_services_enabled?
        VCAP::CloudController::Config.config.get(:volume_services_enabled)
      end

      def get_space_id_from_guid(space_guid)
        space = Space.first(guid: space_guid)
        raise ServiceBrokerCreate::SpaceNotFound unless space

        space.id
      end
    end
  end
end
