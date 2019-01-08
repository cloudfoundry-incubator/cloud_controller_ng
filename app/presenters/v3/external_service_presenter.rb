require 'presenters/v3/base_presenter'
require 'models/helpers/label_helpers'
require 'presenters/mixins/metadata_presentation_helpers'

module VCAP::CloudController
  module Presenters
    module V3
      class ExternalServicePresenter < BasePresenter
        def to_hash
          {
            guid: external_service.guid,
            name: external_service.label,
            description: external_service.description,
            created_at: external_service.created_at,
            updated_at: external_service.updated_at,
            links: build_links,
          }
        end

        private

        def external_service
          @resource
        end

        def build_relationships
          if external_service.space_guid.nil?
            {}
          else
            {
              space: {
                data: {
                  guid: external_service.space_guid
                }
              }
            }
          end
        end

        def build_links
          url_builder = VCAP::CloudController::Presenters::ApiUrlBuilder.new

          { self:
            {
              href: url_builder.build_url(path: "/v3/external_services/#{external_service.guid}")
            }
          }
        end
      end
    end
  end
end
