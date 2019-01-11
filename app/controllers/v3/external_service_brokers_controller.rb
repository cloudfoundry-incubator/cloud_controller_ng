require 'messages/service_brokers_list_message'
require 'presenters/v3/service_broker_presenter'
require 'fetchers/service_broker_list_fetcher'

class ExternalServiceBrokersController < ApplicationController
  def index
    message = ServiceBrokersListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    brokers = list_brokers
    render status: :ok,
           json: Presenters::V3::PaginatedListPresenter.new(
             presenter: Presenters::V3::ServiceBrokerPresenter,
             paginated_result: PaginatedResult.new(brokers, 0, message.pagination_options),
             path: '/v3/external_service_brokers',
          )
  end

  def list_brokers
    brokers = JSON.parse(`kubectl get brokers -o json`)

    brokers.fetch("items").map do |broker|
      name = broker.fetch("metadata").fetch("name")
      url = broker.fetch("spec").fetch("url")
      username = broker.fetch("spec").fetch("username")

      ServiceBroker.new(name: name, broker_url: url, auth_username: username)
    end
  end
end
