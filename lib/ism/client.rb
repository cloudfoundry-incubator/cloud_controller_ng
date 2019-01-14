require 'open3'

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

      apply(service_broker_yaml)

      tries = 0
      until get_service_broker(broker.name).dig('status', 'success')
	raise 'broker success not found after creation' if tries == 10

	tries += 1
	sleep 1
      end

      get_service_broker(broker.name)
    end

    def create_service_instance(name, service_id, plan_id)
      guid = SecureRandom.uuid

      service_instance_yaml = "apiVersion: ism.ism.pivotal.io/v1beta1
kind: BrokeredServiceInstance
metadata:
  name: #{guid}
  namespace: default
spec:
  guid: #{guid}
  name: #{name}
  planId: #{plan_id}
  serviceId: #{service_id}"

      output = apply(service_instance_yaml)

      tries = 0
      until get_service_instance(guid).dig('status', 'success')
	raise 'service instance creation success timed out' if tries == 10

	tries += 1
	sleep 1
      end

      get_service_instance(guid)
    end

    def create_binding(instance_guid)
      binding_guid = SecureRandom.uuid

      service_binding_yaml = "apiVersion: ism.ism.pivotal.io/v1beta1
kind: BrokeredServiceBinding
metadata:
  name: #{binding_guid}
  namespace: default
spec:
  serviceInstanceGuid: #{instance_guid}
  platformName: my-cf"

      output = apply(service_binding_yaml)

      name = output.dig("metadata", "name")

      tries = 0
      until get_service_binding(name).dig("status", "credentials")
	raise "credentials not found in status after creation" if tries == 10

	tries += 1
	sleep 1
      end

      get_service_binding(name)
    end

    def list_brokers
      JSON.parse(`kubectl get brokers -o json`)
    end

    def list_services
      JSON.parse(`kubectl get brokeredservices -o json`)
    end

    def list_service_plans
      JSON.parse(`kubectl get brokeredserviceplans -o json`)
    end

    def list_service_instances
      JSON.parse(`kubectl get brokeredserviceinstances -o json`)
    end

    def list_service_bindings
      JSON.parse(`kubectl get brokeredservicebindings -o json`)
    end

    def get_service_broker(broker_name)
      JSON.parse(`kubectl get brokers #{broker_name} -o json`)
    end

    def get_service_instance(instance_name)
      JSON.parse(`kubectl get brokeredserviceinstance #{instance_name} -o json`)
    end

    def get_service_binding(binding_name)
      JSON.parse(`kubectl get brokeredservicebinding #{binding_name} -o json`)
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
