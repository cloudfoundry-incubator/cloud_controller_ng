module VCAP::CloudController
  class ServicePlanVisibilityFetcher
    class << self
      def fetch_orgs(service_plan_guids:, readable_org_guids: nil, omniscient: false)
        dataset = Organization.dataset.
                  join(:service_plan_visibilities, organization_id: Sequel[:organizations][:id]).
                  join(:service_plans, id: Sequel[:service_plan_visibilities][:service_plan_id]).
                  where { Sequel[:service_plans][:guid] =~ service_plan_guids }

        unless omniscient
          dataset = dataset.where { Sequel[:organizations][:guid] =~ readable_org_guids }
        end

        dataset.
          select_all(:organizations).
          distinct.
          all
      end
    end
  end
end
