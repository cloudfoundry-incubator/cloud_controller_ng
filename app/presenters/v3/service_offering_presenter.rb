require 'presenters/v3/base_presenter'
require 'models/helpers/metadata_helpers'
require 'presenters/mixins/metadata_presentation_helpers'
require 'presenters/api_url_builder'

module VCAP::CloudController
  module Presenters
    module V3
      class ServiceOfferingPresenter < BasePresenter
        def to_hash
          {
            guid: service_offering.guid,
            name: service_offering.label,
            description: service_offering.description,
            available: service_offering.active,
            bindable: service_offering.bindable,
            broker_service_offering_metadata: service_offering.extra,
            broker_service_offering_id: service_offering.unique_id,
            tags: service_offering.tags,
            requires: service_offering.requires,
            created_at: service_offering.created_at,
            updated_at: service_offering.updated_at,
            plan_updateable: service_offering.plan_updateable
          }
        end

        private

        def service_offering
          @resource
        end
      end
    end
  end
end
