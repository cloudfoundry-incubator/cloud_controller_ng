require 'presenters/system_environment/system_env_presenter'
require 'cloud_controller/diego/normal_env_hash_to_diego_env_array_philosopher'
require_relative '../../vcap/vars_builder'

module VCAP::CloudController
  module Diego
    class Environment
      EXCLUDE = [:users].freeze

      def initialize(process, initial_env={})
        @process     = process
        @initial_env = initial_env || {}
      end

      def as_json(_={})
        service_bindings = ISM::Client.new.list_service_bindings.fetch('items')
        diego_env =
          @initial_env.
          merge(process.environment_json || {}).
          merge('VCAP_APPLICATION' => vcap_application, 'MEMORY_LIMIT' => "#{process.memory}m").
          merge(SystemEnvPresenter.new(service_bindings).system_env).
          merge('EDANDAARTISTATICENV' => "hooray")

        diego_env = diego_env.merge(DATABASE_URL: process.database_uri) if process.database_uri

        NormalEnvHashToDiegoEnvArrayPhilosopher.muse(diego_env)
      end

      private

      attr_reader :process

      def vcap_application
        VCAP::VarsBuilder.new(process).to_hash.reject do |k, _v|
          EXCLUDE.include? k
        end
      end
    end
  end
end
