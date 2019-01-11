require 'open3'

module VCAP::CloudController
  class ServiceBrokerMigrate

    def migrate(broker)
    service_broker_yaml = "apiVersion: ism.ism.pivotal.io/v1beta1
kind: Broker
metadata:
  name: #{broker.name}
  namespace: default
spec:
  url: #{broker.broker_url}
  username: #{broker.auth_username}
  password: #{broker.auth_password}"

    result = apply(service_broker_yaml)

    result
    end


    def apply(yaml)
      output, _, _ = Open3.capture3("kubectl apply -o json -f -", stdin_data: yaml)

      JSON.parse(output)
    end
  end
end

