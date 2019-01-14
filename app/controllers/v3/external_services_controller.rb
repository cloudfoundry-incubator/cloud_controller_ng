require 'presenters/v3/external_service_presenter'

class ExternalServicesController < ApplicationController
  def index
    external_services = list_external_services
    render status: :ok,
           json: Presenters::V3::PaginatedListPresenter.new(
             presenter: Presenters::V3::ExternalServicePresenter,
             paginated_result: PaginatedResult.new(external_services, 0, PaginationOptions.from_params({})),
             path: '/v3/external_services',
          )
  end

  def list_external_services()
    external_services = ism_client.list_services

    external_services.fetch("items").map do |service|
      name = service.fetch("spec").fetch("name")
      description = service.fetch("spec").fetch("description")
      guid = service.fetch("spec").fetch("id")

      Service.new(label: name, description: description, guid: guid)
    end
  end

  def ism_client
    @ism_client ||= ISM::Client.new
  end
end
