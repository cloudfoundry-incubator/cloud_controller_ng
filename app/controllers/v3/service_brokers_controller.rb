require 'messages/service_brokers_list_message'
require 'presenters/v3/service_broker_presenter'
require 'fetchers/service_broker_list_fetcher'

class ServiceBrokersController < ApplicationController
  def index
    message = ServiceBrokersListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    # dataset = if permission_queryer.can_read_globally?
    #             ServiceBrokerListFetcher.new.fetch(message: message)
    #           else
    #             ServiceBrokerListFetcher.new.fetch(message: message, permitted_space_guids: permission_queryer.space_developer_space_guids)
    #           end

    brokers = list_brokers(message.space_guids[0])
    render status: :ok,
           json: Presenters::V3::PaginatedListPresenter.new(
             presenter: Presenters::V3::ServiceBrokerPresenter,
             paginated_result: PaginatedResult.new(brokers, 0, message.pagination_options),
             path: '/v3/service_brokers',
          )

    # render status: :ok, json: list_brokers
  end

  def list_brokers(space_guid)
    brokers = JSON.parse(`kubectl get brokers -l space_guid="#{space_guid}" -o json`)

    name = brokers.fetch("items")[0].fetch("spec").fetch("name")
    url = brokers.fetch("items")[0].fetch("spec").fetch("url")
    username = brokers.fetch("items")[0].fetch("spec").fetch("username")

    [ServiceBroker.new(name: name, broker_url: url, auth_username: username)]
  end


end
