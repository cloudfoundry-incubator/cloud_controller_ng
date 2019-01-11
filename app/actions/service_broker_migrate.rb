require 'open3'
require 'ism/client'

module VCAP::CloudController
  class ServiceBrokerMigrate
    def migrate(broker)
      migrate_broker(broker)
    end

    def migrate_broker(broker)
      client = ISM::Client.new
      client.create_broker(broker)
    end
  end
end

