require 'presenters/v3/external_service_instance_presenter'
require 'messages/external_service_instance_create_message'
require 'securerandom'

class ExternalServiceInstancesController < ApplicationController
  def index
    external_service_instances = list_external_service_instances
    render status: :ok,
           json: Presenters::V3::PaginatedListPresenter.new(
             presenter: Presenters::V3::ExternalServiceInstancePresenter,
             paginated_result: PaginatedResult.new(external_service_instances, 0, PaginationOptions.from_params({})),
             path: '/v3/external_service_instances',
          )
  end

  def create
    message = ExternalServiceInstanceCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    guid = SecureRandom.uuid

    service_yaml = "apiVersion: ism.ism.pivotal.io/v1beta1
kind: BrokeredServiceInstance
metadata:
  name: #{guid}
  namespace: default
spec:
  guid: #{guid}
  name: #{message.name}
  planId: #{message.planId}
  serviceId: #{message.serviceId}"

    require 'open3'
    output, _, _ = Open3.capture3("kubectl apply -o json -f -", stdin_data: service_yaml)

    tries = 0
    until get_external_service_instance(guid).dig("status", "success")
      raise "timed out creating service instance" if tries == 10

      tries += 1
      sleep 1
    end

		service = get_external_service_instance(guid)

    render status: :created, json: service_instance_from_external(service)
  end

  def get_external_service_instance(instance_name)
    JSON.parse(`kubectl get brokeredserviceinstance #{instance_name} -o json`)
  end


  def list_external_service_instances()
    external_service_instances = JSON.parse(`kubectl get brokeredserviceinstances -o json`)

    external_service_instances.fetch("items").map do |service|
      service_instance_from_external(service)
    end
  end

  def service_instance_from_external(service)
      id = service.fetch("spec").fetch("guid")
      name = service.fetch("spec").fetch("name")
      serviceId = service.fetch("spec").fetch("serviceId")
      planId = service.fetch("spec").fetch("planId")

      {
        name: name,
        serviceId: serviceId,
        planId: planId,
        guid: id
      }
  end
end
