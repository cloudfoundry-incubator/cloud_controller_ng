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

    guid = SecureRandom.uuid

    service_binding_yaml = "apiVersion: ism.ism.pivotal.io/v1beta1
kind: BrokeredServiceBinding
metadata:
  name: #{guid}
  namespace: default
spec:
  serviceInstanceGuid: #{message.serviceInstanceGuid}
  platformName: my-cf"

    require 'open3'
    output, _, _ = Open3.capture3("kubectl apply -o json -f -", stdin_data: service_binding_yaml)

    external_binding = JSON.parse(output)

    name = external_binding.dig("metadata", "name")

    until get_external_service_binding(name).dig("status", "credentials")
      sleep 1
    end

    external_binding = get_external_service_binding(name)

    render status: :created, json: service_binding_from_external(external_binding)
  end

  def list_external_service_bindings()
    external_service_bindings = JSON.parse(`kubectl get brokeredservicebindings -o json`)

    external_service_bindings.fetch("items").map do |external_binding|
      service_binding_from_external(external_binding)
    end
  end

  def get_external_service_binding(binding_name)
    JSON.parse(`kubectl get brokeredservicebindings #{binding_name} -o json`)
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
end
