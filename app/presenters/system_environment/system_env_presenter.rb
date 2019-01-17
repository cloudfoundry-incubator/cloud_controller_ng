require 'presenters/system_environment/service_instance_presenter'
require 'presenters/system_environment/service_binding_presenter'

class SystemEnvPresenter
  def initialize(service_bindings)
    @service_bindings = service_bindings
  end

  def system_env
    { VCAP_SERVICES: service_binding_env_variables }
  end

  private

  def service_binding_env_variables
    services_hash = {}
    @service_bindings.each do |service_binding|
      service_name = "awesome-service"
      services_hash[service_name.to_sym] ||= []
      services_hash[service_name.to_sym] << {credentials: service_binding.credentials}
    end
    services_hash
  end

  def service_binding_env_values(service_binding)
    ServiceBindingPresenter.new(service_binding, include_instance: false)
  end

  def service_binding_label(service_binding)
    'awesome-service'
  end
end
