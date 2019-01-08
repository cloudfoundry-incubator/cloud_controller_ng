require 'presenters/v3/external_service_presenter'

class ExternalServicesController < ApplicationController
  def index
    # message = ServiceBrokersListMessage.from_params(query_params)
    # invalid_param!(message.errors.full_messages) unless message.valid?
    #
    # dataset = if permission_queryer.can_read_globally?
    #             ServiceBrokerListFetcher.new.fetch(message: message)
    #           else
    #             ServiceBrokerListFetcher.new.fetch(message: message, permitted_space_guids: permission_queryer.space_developer_space_guids)
    #           end

    external_services = list_external_services
    render status: :ok,
           json: Presenters::V3::PaginatedListPresenter.new(
             presenter: Presenters::V3::ExternalServicePresenter,
             paginated_result: PaginatedResult.new(external_services, 0, PaginationOptions.from_params({})),
             path: '/v3/external_services',
          )

    # render status: :ok, json: list_external_services
  end

  def list_external_services()
    external_services = JSON.parse(`kubectl get brokeredservices -o json`)

    external_services.fetch("items").map do |service|
      name = service.fetch("spec").fetch("name")
      description = service.fetch("spec").fetch("description")
      guid = service.fetch("spec").fetch("id")

      Service.new(label: name, description: description, guid: guid)
    end
  end
end
