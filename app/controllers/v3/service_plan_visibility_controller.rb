# require 'presenters/v3/service_plan_presenter'
# require 'fetchers/service_plan_list_fetcher'
require 'fetchers/service_plan_fetcher'
require 'controllers/v3/mixins/service_permissions'
# require 'messages/service_plans_list_message'
# require 'actions/service_plan_delete'
# require 'messages/metadata_update_message'
# require 'actions/transactional_metadata_update'

class ServicePlanVisibilityController < ApplicationController
  include ServicePermissions

  def show
    service_plan = ServicePlanFetcher.fetch(hashed_params[:guid])
    # service_plan_not_found! if service_plan.nil?
    service_plan_not_found! unless visible_to_current_user?(plan: service_plan)
    #
    # presenter = Presenters::V3::ServicePlanPresenter.new(service_plan)
    render status: :ok, json: present(service_plan).to_json
  end

  private

  def present(service_plan)
    if service_plan.public?
      { type: 'public' }
    elsif service_plan.broker_space_scoped?
      {
        type: 'space',
        space: {
          name: service_plan.service_broker.space.name,
          guid: service_plan.service_broker.space.guid,
        }
      }
    else
      {type: 'admin'}
    end
  end

  def service_plan_not_found!
    resource_not_found!(:service_plan)
  end
end
