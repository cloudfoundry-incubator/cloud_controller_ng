require 'messages/role_create_message'
require 'messages/roles_list_message'
require 'actions/role_create'
require 'actions/role_guid_populate'
require 'presenters/v3/role_presenter'

class RolesController < ApplicationController
  def create
    message = RoleCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    if message.space_guid
      space = Space.find(guid: message.space_guid)
      unprocessable_space! unless space
      org = space.organization

      unprocessable_space! if permission_queryer.can_read_from_org?(org.guid) &&
        !permission_queryer.can_read_from_space?(message.space_guid, org.guid)

      unauthorized! unless permission_queryer.can_update_space?(message.space_guid, org.guid)
      user = fetch_user(message)
      unprocessable_user! unless user

      role = RoleCreate.create_space_role(type: message.type, user: user, space: space)
    else
      org = Organization.find(guid: message.organization_guid)
      unprocessable_organization! unless org
      unauthorized! unless permission_queryer.can_write_to_org?(message.organization_guid)
      user = fetch_user(message)
      unprocessable_user! unless user

      role = RoleCreate.create_organization_role(type: message.type, user: user, organization: org)
    end

    render status: :created, json: Presenters::V3::RolePresenter.new(role)
  rescue RoleCreate::Error => e
    unprocessable!(e)
  end

  def index
    message = RolesListMessage.from_params(query_params)
    unprocessable!(message.errors.full_messages) unless message.valid?

    RoleGuidPopulate.populate
    roles = readable_roles

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::RolePresenter,
      paginated_result: SequelPaginator.new.get_page(roles, message.try(:pagination_options)),
      path: '/v3/roles',
      message: message
    )
  end

  private

  def fetch_user(message)
    user_guid = message.user_guid || guid_for_uaa_user(message.user_name, message.user_origin)
    readable_users.first(guid: user_guid)
  end

  def readable_users
    User.readable_users_for_current_user(permission_queryer.can_read_globally?, current_user)
  end

  def readable_roles
    visible_user_ids = readable_users.select(:id)

    roles_for_visible_users = Role.where(user_id: visible_user_ids)
    roles_in_visible_spaces = roles_for_visible_users.filter(space_id: visible_space_ids)
    roles_in_visible_orgs = roles_for_visible_users.filter(organization_id: visible_org_ids)

    roles_in_visible_spaces.union(roles_in_visible_orgs)
  end

  def visible_space_ids
    if permission_queryer.can_read_globally?
      Space.dataset.select(:id)
    else
      Space.user_visibility_filter(current_user)[:spaces__id]
    end
  end

  def visible_org_ids
    if permission_queryer.can_read_globally?
      Organization.dataset.select(:id)
    else
      Organization.user_visibility_filter(current_user)[:id]
    end
  end

  def unprocessable_space!
    unprocessable!('Invalid space. Ensure that the space exists and you have access to it.')
  end

  def unprocessable_organization!
    unprocessable!('Invalid organization. Ensure that the organization exists and you have access to it.')
  end

  def unprocessable_user!
    unprocessable!('Invalid user. Ensure that the user exists and you have access to it.')
  end

  def guid_for_uaa_user(username, given_origin)
    uaa_client = CloudController::DependencyLocator.instance.uaa_client

    origin = if given_origin
               given_origin
             else
               origins = uaa_client.origins_for_username(username)

               if origins.length > 1
                 unprocessable!(
                   "Ambiguous user. User with username '#{username}' exists in the following origins: "\
                   "#{origins.join(', ')}. Specify an origin to disambiguate."
                 )
               end

               origins[0]
             end

    guid = uaa_client.id_for_username(username, origin: origin)

    unless guid
      if given_origin
        unprocessable!("No user exists with the username '#{username}' and origin '#{origin}'.")
      else
        unprocessable!("No user exists with the username '#{username}'.")
      end
    end

    guid
  end
end
