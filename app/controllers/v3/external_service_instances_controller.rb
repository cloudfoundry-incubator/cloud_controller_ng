require 'presenters/v3/external_service_instance_presenter'

class ExternalServiceInstancesController < ApplicationController
  def index
    # message = ServiceBrokersListMessage.from_params(query_params)
    # invalid_param!(message.errors.full_messages) unless message.valid?
    #
    # dataset = if permission_queryer.can_read_globally?
    #             ServiceBrokerListFetcher.new.fetch(message: message)
    #           else
    #             ServiceBrokerListFetcher.new.fetch(message: message, permitted_space_guids: permission_queryer.space_developer_space_guids)
    #           end

    external_service_instances = list_external_service_instances
    render status: :ok,
           json: Presenters::V3::PaginatedListPresenter.new(
             presenter: Presenters::V3::ExternalServiceInstancePresenter,
             paginated_result: PaginatedResult.new(external_service_instances, 0, PaginationOptions.from_params({})),
             path: '/v3/external_service_instances',
          )
  end

  def list_external_service_instances()
    external_service_instances = JSON.parse(`kubectl get brokeredserviceinstances -o json`)

    external_service_instances.fetch("items").map do |service|
      id = service.fetch("spec").fetch("id")
      name = service.fetch("spec").fetch("name")
      serviceName = service.fetch("spec").fetch("service")
      planName = service.fetch("spec").fetch("plan")

      {
        name: name,
        service: serviceName,
        plan: planName,
        guid: id
      }
    end
  end
end
