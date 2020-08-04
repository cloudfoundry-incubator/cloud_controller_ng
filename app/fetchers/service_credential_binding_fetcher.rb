module VCAP
  module CloudController
    class ServiceCredentialBindingFetcher
      ServiceInstanceCredential = Struct.new(
        :guid, :type, :name, :created_at, :updated_at, :service_instance_guid, :app_guid,
        :last_operation_id, :last_operation_type, :last_operation_state, :last_operation_description, :last_operation_created_at, :last_operation_updated_at
      ).freeze

      def fetch(guid, space_guids:)
        list_fetcher.fetch(space_guids: space_guids).first(guid: guid).try do |db_binding|
          ServiceInstanceCredential.new(
            db_binding.guid,
            db_binding.type,
            db_binding.name,
            db_binding.created_at,
            db_binding.updated_at,
            db_binding.service_instance_guid,
            db_binding.app_guid,
            db_binding.last_operation_id,
            db_binding.last_operation_type,
            db_binding.last_operation_state,
            db_binding.last_operation_description,
            db_binding.last_operation_created_at,
            db_binding.last_operation_updated_at
          )
        end
      end

      private

      def list_fetcher
        ServiceCredentialBindingListFetcher.new
      end
    end
  end
end
