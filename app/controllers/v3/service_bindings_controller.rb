require 'fetchers/service_binding_create_fetcher'
require 'fetchers/service_binding_list_fetcher'
require 'presenters/v3/service_binding_presenter'
require 'messages/service_binding_create_message'
require 'messages/service_bindings_list_message'
require 'actions/service_binding_create'
require 'actions/service_binding_delete'
require 'controllers/v3/mixins/app_sub_resource'

class ServiceBindingsController < ApplicationController
  include AppSubResource

  def create
    message = ServiceBindingCreateMessage.new(params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    app, service_instance = ServiceBindingCreateFetcher.new.fetch(message.app_guid, message.service_instance_guid)
    app_not_found! unless app
    service_instance_not_found! unless service_instance
    unauthorized! unless can_write?(app.space.guid)
    raise CloudController::Errors::ApiError.new_from_details('RouteServiceNotBindableToApp') if service_instance.route_service?

    accepts_incomplete = false
    begin
      service_binding = ServiceBindingCreate.new(user_audit_info).create(app, service_instance, message, volume_services_enabled?, accepts_incomplete)
      render status: :created, json: Presenters::V3::ServiceBindingPresenter.new(service_binding)
    rescue ServiceBindingCreate::ServiceInstanceNotBindable
      raise CloudController::Errors::ApiError.new_from_details('UnbindableService')
    rescue ServiceBindingCreate::VolumeMountServiceDisabled
      raise CloudController::Errors::ApiError.new_from_details('VolumeMountServiceDisabled')
    rescue ServiceBindingCreate::InvalidServiceBinding
      raise CloudController::Errors::ApiError.new_from_details('ServiceBindingAppServiceTaken', "#{app.guid} #{service_instance.guid}")
    end
  end

  def show
    service_binding = VCAP::CloudController::ServiceBinding.find(guid: params[:guid])

    binding_not_found! unless service_binding && can_read?(service_binding.space.guid, service_binding.space.organization.guid)
    render status: :ok, json: Presenters::V3::ServiceBindingPresenter.new(service_binding, show_secrets: can_see_secrets?(service_binding.space))
  end

  def index
    message = ServiceBindingsListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    dataset = if can_read_globally?
                ServiceBindingListFetcher.new(message).fetch_all
              else
                ServiceBindingListFetcher.new(message).fetch(space_guids: readable_space_guids)
              end

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::ServiceBindingPresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: base_url(resource: 'service_bindings'),
      message: message,
    )
  end

  def destroy
    binding = VCAP::CloudController::ServiceBinding.where(guid: params[:guid]).eager(service_instance: { space: :organization }).all.first

    binding_not_found! unless binding && can_read?(binding.space.guid, binding.space.organization.guid)
    unauthorized! unless can_write?(binding.space.guid)

    ServiceBindingDelete.new(user_audit_info).foreground_delete_request(binding)

    head :no_content
  end

  private

  def service_instance_not_found!
    resource_not_found!(:service_instance)
  end

  def binding_not_found!
    resource_not_found!(:service_binding)
  end

  def volume_services_enabled?
    configuration.get(:volume_services_enabled)
  end
end
