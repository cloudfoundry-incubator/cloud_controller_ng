require 'spec_helper'
require 'fetchers/service_plan_visibility_fetcher'

module VCAP::CloudController
  RSpec.describe ServicePlanVisibilityFetcher do
    describe '#fetch_orgs' do
      let!(:org1) { Organization.make }
      let!(:org2) { Organization.make }

      let!(:plan_1) do
        plan = ServicePlan.make
        ServicePlanVisibility.make(service_plan: plan, organization: org1)
        ServicePlanVisibility.make(service_plan: plan, organization: org2)
        plan
      end

      let!(:plan_2) do
        plan = ServicePlan.make
        ServicePlanVisibility.make(service_plan: plan, organization: org2)
        plan
      end

      describe 'visibility of a single plan' do
        context 'when admin' do
          it 'returns the complete list of orgs' do
            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_1.guid],
                     omniscient: true
            )).to contain_exactly(org1, org2)

            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_2.guid],
                     omniscient: true
            )).to contain_exactly(org2)
          end
        end

        context 'when both orgs are visible' do
          it 'returns the complete list of orgs' do
            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_1.guid],
                     readable_org_guids: [org1.guid, org2.guid],
            )).to contain_exactly(org1, org2)

            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_2.guid],
                     readable_org_guids: [org1.guid, org2.guid],
            )).to contain_exactly(org2)
          end
        end

        context 'when only `org2` is visible' do
          it 'only returns `org2`' do
            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_1.guid],
                     readable_org_guids: [org2.guid],
            )).to contain_exactly(org2)

            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_2.guid],
                     readable_org_guids: [org2.guid],
            )).to contain_exactly(org2)
          end
        end

        context 'when only `org1` is visible' do
          it 'only returns `org1` when visible in org1' do
            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_1.guid],
                     readable_org_guids: [org1.guid],
            )).to contain_exactly(org1)
          end

          it 'return empty when the plan is not visible in `org1`' do
            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_2.guid],
                     readable_org_guids: [org1.guid],
            )).to be_empty
          end
        end

        context 'when no orgs are visible' do
          it 'returns an empty list' do
            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_1.guid],
                     readable_org_guids: [],
            )).to be_empty

            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_2.guid],
                     readable_org_guids: [],
            )).to be_empty
          end
        end
      end

      describe 'variable number of plans' do
        context 'when many plans are specified and only one is visible' do
          let!(:plan_alpha) { ServicePlan.make }
          let!(:plan_beta) { ServicePlan.make }

          it 'returns the visible orgs' do
            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_1.guid, plan_alpha.guid, plan_beta.guid],
                     readable_org_guids: [org2.guid]
            )).to contain_exactly(org2)

            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_1.guid, plan_alpha.guid, plan_beta.guid],
                     readable_org_guids: [org1.guid, org2.guid]
            )).to contain_exactly(org1, org2)

            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [plan_1.guid, plan_alpha.guid, plan_beta.guid],
                     omniscient: true
            )).to contain_exactly(org1, org2)
          end
        end

        context 'when no plans are specified' do
          it 'returns an empty list' do
            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [],
                     omniscient: true
            )).to be_empty

            expect(ServicePlanVisibilityFetcher.fetch_orgs(
                     service_plan_guids: [],
                     readable_org_guids: [org1.guid, org2.guid],
            )).to be_empty
          end
        end
      end
    end
  end
end
