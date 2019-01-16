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

    def migrate_service_instance(guid, name, service_id, plan_id)
      service_instance_yaml = "apiVersion: ism.ism.pivotal.io/v1beta1
kind: BrokeredServiceInstance
metadata:
  name: #{guid}
  namespace: default
spec:
  guid: #{guid}
  name: #{name}
  planId: #{plan_id}
  serviceId: #{service_id}
  migrated: true"

      apply_service_instance(service_instance_yaml)
    end

    def migrate_service_binding(guid, instance_guid, app_guid, credentials)
      service_binding_yaml = "apiVersion: ism.ism.pivotal.io/v1beta1
kind: BrokeredServiceBinding
metadata:
  name: #{guid}
  namespace: default
  labels:
    app_guid: #{app_guid}
spec:
  serviceInstanceGuid: #{instance_guid}
  platformName: my-cf
  migrated: true
  migratedCredentials: '#{credentials}'"

      apply_service_binding(service_binding_yaml)
    end

    def create_service_instance(name, service_id, plan_id, space_guid)
      guid = SecureRandom.uuid

      service_instance_yaml = "apiVersion: ism.ism.pivotal.io/v1beta1
kind: BrokeredServiceInstance
metadata:
  name: #{guid}
  namespace: default
  labels:
    space_guid: #{space_guid}
spec:
  guid: #{guid}
  name: #{name}
  planId: #{plan_id}
  serviceId: #{service_id}"

      apply_service_instance(service_instance_yaml)
    end

    def create_binding(instance_guid, app_guid)
      binding_guid = SecureRandom.uuid

      service_binding_yaml = "apiVersion: ism.ism.pivotal.io/v1beta1
kind: BrokeredServiceBinding
metadata:
  name: #{binding_guid}
  namespace: default
  labels:
    app_guid: #{app_guid}
spec:
  serviceInstanceGuid: #{instance_guid}
  platformName: my-cf"

      apply_service_binding(service_binding_yaml)
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

    def list_service_instances_by_space(space_guid)
      JSON.parse(`kubectl get brokeredserviceinstances -o json -l 'space_guid==#{space_guid}'`)
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
      `kubectl delete brokeredservicebindings --all`
    end

    private

    def apply_service_instance(yaml)
      output = apply(yaml)

      guid = output.fetch("metadata").fetch("name")

      tries = 0
      until get_service_instance(guid).dig('status', 'success')
	raise 'service instance creation success timed out' if tries == 10

	tries += 1
	sleep 1
      end

      get_service_instance(guid)
    end

    def apply_service_binding(yaml)
      output = apply(yaml)

      name = output.dig("metadata", "name")

      tries = 0
      until get_service_binding(name).dig("status", "credentials")
	raise 'credentials not found in status after creation' if tries == 10

	tries += 1
	sleep 1
      end

      get_service_binding(name)
    end

    def apply(yaml)
      output, stderr_str, status = Open3.capture3("kubectl apply -o json -f -", stdin_data: yaml)
      JSON.parse(output)
    end
  end
end
