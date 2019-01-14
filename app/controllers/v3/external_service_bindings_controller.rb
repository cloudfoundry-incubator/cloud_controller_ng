require 'presenters/v3/external_service_binding_presenter'
require 'messages/external_service_binding_create_message'
require 'securerandom'

class ExternalServiceBindingsController < ApplicationController
  def index
    external_service_bindings = list_external_service_bindings
    render status: :ok,
           json: Presenters::V3::PaginatedListPresenter.new(
             presenter: Presenters::V3::ExternalServiceBindingPresenter,
             paginated_result: PaginatedResult.new(external_service_bindings, 0, PaginationOptions.from_params({})),
             path: '/v3/external_service_bindings',
          )
  end

  def create
    message = ExternalServiceBindingCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    binding = ism_client.create_binding(message.serviceInstanceGuid)

    external_binding = service_binding_from_external(binding)

    binding = VCAP::CloudController::ExternalServiceBinding.new(app_guid: message.appGuid, credentials: external_binding.fetch(:credentials))
    binding.save

    render status: :created, json: external_binding
  end

  def list_external_service_bindings()
    external_service_bindings = ism_client.list_service_bindings

    external_service_bindings.fetch("items").map do |external_binding|
      service_binding_from_external(external_binding)
    end
  end

  def service_binding_from_external(external_binding)
      guid = external_binding.fetch("metadata").fetch("uid")
      service_instance_guid = external_binding.fetch("spec").fetch("serviceInstanceGuid")
      platform_name = external_binding.fetch("spec").fetch("platformName")
      raw_creds = external_binding.dig("status", "credentials") || ""

      creds = JSON.parse(raw_creds)

      {
        guid: guid,
        serviceInstanceGuid: service_instance_guid,
        platformName: platform_name,
        credentials: creds
      }
  end

  def ism_client
    @ism_client ||= ISM::Client.new
  end
end
