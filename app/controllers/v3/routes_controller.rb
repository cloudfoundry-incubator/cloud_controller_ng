require 'messages/route_create_message'
require 'messages/routes_list_message'
require 'messages/route_show_message'
require 'messages/route_update_message'
require 'messages/route_update_destinations_message'
require 'actions/update_route_destinations'
require 'presenters/v3/route_presenter'
require 'presenters/v3/route_destinations_presenter'
require 'presenters/v3/paginated_list_presenter'
require 'actions/route_create'
require 'actions/route_delete'
require 'actions/route_update'
require 'fetchers/app_fetcher'
require 'fetchers/route_fetcher'

class RoutesController < ApplicationController
  def index
    message = RoutesListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    dataset = RouteFetcher.fetch(
      message,
      permission_queryer.readable_route_guids,
      eager_loaded_associations: Presenters::V3::RoutePresenter.associated_resources
    )

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::RoutePresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: '/v3/routes',
      message: message,
    )
  end

  def show
    message = RouteShowMessage.new({ guid: hashed_params['guid'] })
    unprocessable!(message.errors.full_messages) unless message.valid?

    route = Route.find(guid: message.guid)
    route_not_found! unless route && permission_queryer.can_read_route?(route.space.guid, route.organization.guid)

    render status: :ok, json: Presenters::V3::RoutePresenter.new(route)
  end

  def create
    FeatureFlag.raise_unless_enabled!(:route_creation) unless permission_queryer.can_write_globally?

    message = RouteCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    space = Space.find(guid: message.space_guid)
    domain = Domain.find(guid: message.domain_guid)

    unprocessable_space! unless space
    unprocessable_domain! unless domain
    unauthorized! unless permission_queryer.can_write_to_space?(space.guid)
    unprocessable_wildcard! if domain.shared? && message.wildcard? && !permission_queryer.can_write_globally?

    route = RouteCreate.new(user_audit_info).create(message: message, space: space, domain: domain)

    render status: :created, json: Presenters::V3::RoutePresenter.new(route)
  rescue RouteCreate::Error => e
    unprocessable!(e)
  end

  def update
    route = Route.find(guid: hashed_params[:guid])
    route_not_found! unless route

    message = RouteUpdateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    route_not_found! unless route && permission_queryer.can_read_route?(route.space.guid, route.organization.guid)
    unauthorized! unless permission_queryer.can_write_to_space?(route.space.guid)

    route = VCAP::CloudController::RouteUpdate.new.update(route: route, message: message)

    render status: :ok, json: Presenters::V3::RoutePresenter.new(route)
  end

  def destroy
    message = RouteShowMessage.new({ guid: hashed_params['guid'] })
    unprocessable!(message.errors.full_messages) unless message.valid?

    route = Route.find(guid: message.guid)
    route_not_found! unless route && permission_queryer.can_read_route?(route.space.guid, route.organization.guid)
    unauthorized! unless permission_queryer.can_write_to_space?(route.space.guid)

    delete_action = RouteDeleteAction.new(user_audit_info)
    deletion_job = VCAP::CloudController::Jobs::DeleteActionJob.new(Route, route.guid, delete_action)
    pollable_job = Jobs::Enqueuer.new(deletion_job, queue: Jobs::Queues.generic).enqueue_pollable

    url_builder = VCAP::CloudController::Presenters::ApiUrlBuilder.new
    head :accepted, 'Location' => url_builder.build_url(path: "/v3/jobs/#{pollable_job.guid}")
  end

  def index_destinations
    message = RouteShowMessage.new({ guid: hashed_params['guid'] })
    unprocessable!(message.errors.full_messages) unless message.valid?

    route = Route.find(guid: message.guid)
    route_not_found! unless route && permission_queryer.can_read_route?(route.space.guid, route.organization.guid)

    render status: :ok, json: Presenters::V3::RouteDestinationsPresenter.new(route)
  end

  def insert_destinations
    message = RouteUpdateDestinationsMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    route = Route.find(guid: hashed_params[:guid])
    route_not_found! unless route && permission_queryer.can_read_route?(route.space.guid, route.organization.guid)

    unauthorized! unless permission_queryer.can_write_to_space?(route.space.guid)

    desired_app_guids = message.destinations.map { |dst| HashUtils.dig(dst, :app, :guid) }.compact

    apps_hash = AppModel.where(guid: desired_app_guids).each_with_object({}) { |app, apps_hsh| apps_hsh[app.guid] = app; }
    validate_app_guids!(apps_hash, desired_app_guids)
    validate_app_spaces!(apps_hash, route)

    route = UpdateRouteDestinations.add(message.destinations_array, route, apps_hash, user_audit_info)

    render status: :ok, json: Presenters::V3::RouteDestinationsPresenter.new(route)
  rescue UpdateRouteDestinations::Error => e
    unprocessable!(e.message)
  end

  def replace_destinations
    message = RouteUpdateDestinationsMessage.new(hashed_params[:body], replace: true)
    unprocessable!(message.errors.full_messages) unless message.valid?

    route = Route.find(guid: hashed_params[:guid])
    route_not_found! unless route && permission_queryer.can_read_route?(route.space.guid, route.organization.guid)

    unauthorized! unless permission_queryer.can_write_to_space?(route.space.guid)

    desired_app_guids = message.destinations.map { |dst| HashUtils.dig(dst, :app, :guid) }.compact

    apps_hash = AppModel.where(guid: desired_app_guids).each_with_object({}) { |app, apps_hsh| apps_hsh[app.guid] = app; }
    validate_app_guids!(apps_hash, desired_app_guids)
    validate_app_spaces!(apps_hash, route)

    route = UpdateRouteDestinations.replace(message.destinations_array, route, apps_hash, user_audit_info)

    render status: :ok, json: Presenters::V3::RouteDestinationsPresenter.new(route)
  rescue UpdateRouteDestinations::DuplicateDestinationError => e
    unprocessable!(e.message)
  end

  def destroy_destination
    route = Route.find(guid: hashed_params[:guid])
    route_not_found! unless route && permission_queryer.can_read_route?(route.space.guid, route.organization.guid)
    unauthorized! unless permission_queryer.can_write_to_space?(route.space.guid)

    destination = RouteMappingModel.find(guid: hashed_params[:destination_guid])
    unprocessable_destination! unless destination

    UpdateRouteDestinations.delete(destination, route, user_audit_info)

    head :no_content
  rescue UpdateRouteDestinations::Error => e
    unprocessable!(e.message)
  end

  def index_by_app
    message = RoutesListMessage.from_params(query_params).for_app_guid(hashed_params['guid'])
    invalid_param!(message.errors.full_messages) unless message.valid?

    app, space, org = AppFetcher.new.fetch(hashed_params['guid'])
    app_not_found! unless app && permission_queryer.can_read_from_space?(space.guid, org.guid)

    dataset = RouteFetcher.fetch(
      message,
      permission_queryer.readable_route_guids,
      eager_loaded_associations: Presenters::V3::RoutePresenter.associated_resources
    )

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::RoutePresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: "/v3/apps/#{app.guid}/routes",
      message: message,
    )
  end

  private

  def route_not_found!
    resource_not_found!(:route)
  end

  def unprocessable_destination!
    unprocessable!('Unable to unmap route from destination. Ensure the route has a destination with this guid.')
  end

  def unprocessable_wildcard!
    unprocessable!('You do not have sufficient permissions to create a route with a wildcard host on a domain not scoped to an organization.')
  end

  def unprocessable_space!
    unprocessable!('Invalid space. Ensure that the space exists and you have access to it.')
  end

  def unprocessable_domain!
    unprocessable!('Invalid domain. Ensure that the domain exists and you have access to it.')
  end

  def validate_app_guids!(apps_hash, desired_app_guids)
    existing_app_guids = apps_hash.keys

    missing_app_guids = desired_app_guids - (existing_app_guids & permission_queryer.readable_app_guids)

    unprocessable!("App(s) with guid(s) \"#{missing_app_guids.join('", "')}\" do not exist or you do not have access.") unless missing_app_guids.empty?
  end

  def validate_app_spaces!(apps_hash, route)
    if apps_hash.values.any? { |app| app.space != route.space }
      unprocessable!('Routes cannot be mapped to destinations in different spaces.')
    end
  end

  def app_not_found!
    resource_not_found!(:app)
  end
end
