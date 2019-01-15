require 'presenters/v3/external_service_instance_presenter'
require 'messages/external_service_instance_create_message'
require 'securerandom'
require 'ism/client'

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

    service = ism_client.create_service_instance(message.name, message.serviceId, message.planId)

    render status: :created, json: service_instance_from_external(service)
  end

  def list_external_service_instances
    external_service_instances = ism_client.list_service_instances

    external_service_instances.fetch('items').map do |service|
      service_instance_from_external(service)
    end
  end

  def service_instance_from_external(service)
    id = service.fetch('spec').fetch('guid')
    name = service.fetch('spec').fetch('name')
    serviceId = service.fetch('spec').fetch('serviceId')
    planId = service.fetch('spec').fetch('planId')

    {
      name: name,
      serviceId: serviceId,
      planId: planId,
      guid: id
    }
  end

  def ism_client
    @ism_client ||= ISM::Client.new
  end
end