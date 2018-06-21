require 'vcap/services/api'
require 'actions/services/service_key_delete'
require 'actions/services/service_key_create'

module VCAP::CloudController
  class ServiceKeysController < RestController::ModelController
    ERROR_MESSAGES = {
      service_instance_not_bindable: "This service doesn't support creation of keys.",
      service_instance_is_user_provided: 'Service keys are not supported for user-provided service instances.'
    }.freeze
    private_constant :ERROR_MESSAGES

    define_attributes do
      to_one :service_instance
      attribute :name, String
      attribute :parameters, Hash, default: nil
    end

    get path, :enumerate

    query_parameters :name, :service_instance_guid

    def self.not_found_exception(guid, _find_model)
      CloudController::Errors::ApiError.new_from_details('ServiceKeyNotFound', guid)
    end

    def self.dependencies
      [:services_event_repository, :service_key_credential_object_renderer, :service_key_credential_collection_renderer]
    end

    def inject_dependencies(dependencies)
      super
      @services_event_repository = dependencies.fetch(:services_event_repository)
      @object_renderer = dependencies[:service_key_credential_object_renderer]
      @collection_renderer = dependencies[:service_key_credential_collection_renderer]
    end

    post path, :create
    def create
      accepts_incomplete = convert_flag_to_bool(params['accepts_incomplete'])

      @request_attrs = self.class::CreateMessage.decode(body).extract(stringify_keys: true)
      logger.debug 'cc.create', model: self.class.model_class_name, attributes: request_attrs
      raise InvalidRequest unless request_attrs

      service_instance = ServiceInstance.first(guid: request_attrs['service_instance_guid'])
      raise CloudController::Errors::ApiError.new_from_details('ServiceInstanceNotFound', @request_attrs['service_instance_guid']) unless service_instance
      raise CloudController::Errors::ApiError.new_from_details('ServiceKeyNotSupported', ERROR_MESSAGES[:service_instance_not_bindable]) unless service_instance.bindable?
      if service_instance.user_provided_instance?
        raise CloudController::Errors::ApiError.new_from_details('ServiceKeyNotSupported', ERROR_MESSAGES[:service_instance_is_user_provided])
      end

      service_key = ServiceKey.new(request_attrs.except('parameters'))
      validate_access(:create, service_key)
      raise Sequel::ValidationFailed.new(service_key) unless service_key.valid?

      service_key, errors = ServiceKeyCreate.new(logger).create(
        service_instance,
        request_attrs.except('parameters'),
        request_attrs['parameters'],
        accepts_incomplete
      )

      if errors.present?
        raise errors.first
      end

      @services_event_repository.record_service_key_event(:create, service_key)

      [status_from_operation_state(service_key.last_operation),
       { 'Location' => "#{self.class.path}/#{service_key.guid}" },
       object_renderer.render_json(self.class, service_key, @opts)
      ]
    rescue ServiceKeyCreate::ServiceBrokerInvalidServiceKeyRetrievable
      raise CloudController::Errors::ApiError.new_from_details('ServiceKeyInvalid', 'Could not create asynchronous service key when bindings_retrievable is false.')
    end

    delete path_guid, :delete
    def delete(guid)
      accepts_incomplete = convert_flag_to_bool(params['accepts_incomplete'])
      begin
        service_key = find_guid_and_validate_access(:delete, guid, ServiceKey)
      rescue CloudController::Errors::ApiError => e
        e.name == 'NotAuthorized' ? raise(CloudController::Errors::ApiError.new_from_details('ServiceKeyNotFound', guid)) : raise(e)
      end

      delete_action = ServiceKeyDelete.new(accepts_incomplete)
      errors, warnings = delete_action.delete(service_key)
      raise errors.first unless errors.empty?
      add_warnings_from_service_key_delete!(warnings)

      @services_event_repository.record_service_key_event(:delete, service_key)

      if accepts_incomplete && service_key.exists?
        [HTTP::ACCEPTED,
         { 'Location' => "#{self.class.path}/#{service_key.guid}" },
         object_renderer.render_json(self.class, service_key, @opts)
        ]
      else
        [HTTP::NO_CONTENT, nil]
      end
    end

    get '/v2/service_keys/:guid', :read
    def read(guid)
      begin
        service_key = find_guid_and_validate_access(:read, guid, ServiceKey)
      rescue CloudController::Errors::ApiError => e
        e.name == 'NotAuthorized' ? raise(CloudController::Errors::ApiError.new_from_details('ServiceKeyNotFound', guid)) : raise(e)
      end

      [HTTP::OK,
       { 'Location' => "#{self.class.path}/#{service_key.guid}" },
       object_renderer.render_json(self.class, service_key, @opts)
      ]
    end

    get '/v2/service_keys/:guid/parameters', :parameters
    def parameters(guid)
      service_key = find_guid_and_validate_access(:read, guid)

      fetcher = ServiceBindingRead.new
      parameters = fetcher.fetch_parameters(service_key)
      [HTTP::OK, parameters.to_json]
    rescue ServiceBindingRead::NotSupportedError
      raise CloudController::Errors::ApiError.new_from_details('ServiceKeyNotSupported', 'This service does not support fetching service key parameters.')
    rescue CloudController::Errors::ApiError => e
      e.name == 'NotAuthorized' ? raise(CloudController::Errors::ApiError.new_from_details('ServiceKeyNotFound', guid)) : raise(e)
    end

    def self.translate_validation_exception(e, attributes)
      unique_errors = e.errors.on([:name, :service_instance_id])
      if unique_errors && unique_errors.include?(:unique)
        CloudController::Errors::ApiError.new_from_details('ServiceKeyNameTaken', attributes['name'])
      elsif e.errors.on(:service_instance) && e.errors.on(:service_instance).include?(:presence)
        CloudController::Errors::ApiError.new_from_details('ServiceInstanceNotFound', attributes['service_instance_guid'])
      else
        CloudController::Errors::ApiError.new_from_details('ServiceKeyInvalid', e.errors.full_messages)
      end
    end

    define_messages

    private

    def status_from_operation_state(last_operation)
      if last_operation && last_operation.state == 'in progress'
        HTTP::ACCEPTED
      else
        HTTP::CREATED
      end
    end

    def add_warnings_from_service_key_delete!(warnings)
      warnings.each do |warning|
        add_warning(warning)
      end
    end
  end
end
