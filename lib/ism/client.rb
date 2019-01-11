module ISM
  class Client

    def create_broker(broker)
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

			tries = 0
      until get_external_service_broker(broker.name).dig("status", "success")
				raise "broker not found after creation" if tries == 10

				tries += 1
        sleep 1
      end

      result
    end


    def get_external_service_broker(broker_name)
      JSON.parse(`kubectl get brokers #{broker_name} -o json`)
    end

    def create_service_instance

    end

    def create_service_binding

    end

    def cleanup
      `kubectl delete brokers --all`
      `kubectl delete brokeredservices --all`
      `kubectl delete brokeredserviceplans --all`
      `kubectl delete brokeredserviceinstances --all`
      `kubectl delete brokeredserviceplans --all`
    end

    private

    def apply(yaml)
      output, _, _ = Open3.capture3("kubectl apply -o json -f -", stdin_data: yaml)
      JSON.parse(output)
    end
  end
end
