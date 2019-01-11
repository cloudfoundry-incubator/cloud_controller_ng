require 'presenters/v3/external_service_plan_presenter'

class ExternalServicePlansController < ApplicationController
  def index
    external_service_plans = list_external_service_plans
    render status: :ok,
           json: Presenters::V3::PaginatedListPresenter.new(
             presenter: Presenters::V3::ExternalServicePlanPresenter,
             paginated_result: PaginatedResult.new(external_service_plans, 0, PaginationOptions.from_params({})),
             path: '/v3/external_service_plans',
          )
  end

  def list_external_service_plans()
    external_service_plans = JSON.parse(`kubectl get brokeredserviceplans -o json`)

    external_service_plans.fetch("items").map do |service|
      name = service.fetch("spec").fetch("name")
      description = service.fetch("spec").fetch("description")
      guid = service.fetch("spec").fetch("id")

      ServicePlan.new(name: name, description: description, guid: guid)
    end
  end
end
