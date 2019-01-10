require 'models/helpers/process_types'

module VCAP::CloudController
  class ExternalServiceBinding < Sequel::Model
    include Serializer

    plugin :after_initialize

    many_to_one :app, class: 'VCAP::CloudController::AppModel', key: :app_guid, primary_key: :guid, without_guid_generation: true

    # serializes_via_json :credentials

    def to_hash(_opts={})
      { guid: guid }
    end

    def after_initialize
      super
      self.guid ||= SecureRandom.uuid
    end

    def self.user_visibility_filter(user)
      { app: AppModel.user_visible(user) }
    end
  end
end
