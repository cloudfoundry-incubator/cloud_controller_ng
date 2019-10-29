module VCAP::CloudController
  class ServiceBrokerUpdateCred < Sequel::Model
    import_attributes :password
    set_field_as_encrypted :password
  end
end