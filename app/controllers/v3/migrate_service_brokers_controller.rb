require 'actions/service_broker_migrate'

class MigrateServiceBrokersController < ApplicationController
  def migrate
    # parse the message for broker guid
    body = hashed_params[:body]

    broker_guid = body.fetch(:broker_guid)

    # lookup broker from model
    broker = ServiceBroker.find(guid: broker_guid)

    # create the broker in ISM

    result = ServiceBrokerMigrate.new.migrate(broker)

    # delete the broker from model
    broker.destroy

    render status: :created, json: result
  end
end
