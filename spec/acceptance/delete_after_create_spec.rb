require 'spec_helper'
require 'actions/services/service_instance_create'

class FakeEnqueuer
  attr_reader :job, :enqueued

  def initialize(job)
    @job = job
  end

  def enqueue
    @enqueued = true
  end
end

module VCAP::CloudController
  RSpec.describe 'Delete after create' do
    let(:racecar) { Racecar.new(expected_race, true) }

    let(:space) { Space.make }
    let(:user) { User.make }
    let(:service_plan) { ServicePlan.make }
    let(:event_repository) { instance_double(Repositories::ServiceEventRepository, record_service_instance_event: nil, user_audit_info: user_audit_info) }
    let(:user_audit_info) { instance_double(UserAuditInfo, user_guid: user.guid, user_email: 'just-a-string@example.org', user_name: 'John') }
    let(:logger) { double(:logger) }
    let(:create_action) { ServiceInstanceCreate.new(event_repository, logger, racecar) }
    let(:request_attrs) do
      {
        'space_guid' => space.guid,
        'service_plan_guid' => service_plan.guid,
        'name' => 'my-instance',
        'dashboard_url' => 'test-dashboardurl.com'
      }
    end

    let(:dashboard_url) { 'com' }
    let(:broker_response_body) { { credentials: {}, dashboard_url: dashboard_url } }
    let(:create_last_operation) { { type: 'create', description: '', broker_provided_operation: nil, state: 'in progress' } }
    let(:client) { instance_double(VCAP::Services::ServiceBrokers::V2::Client) }

    let!(:service_instance) { ManagedServiceInstance.make }
    let(:delete_last_operation) { { type: 'delete', description: '', broker_provided_operation: nil, state: 'in progress' } }

    let(:delete_action) { ServiceInstanceDelete.new(event_repository: event_repository) }

    before do
      @queue = []

      allow(VCAP::Services::ServiceClientProvider).to receive(:provide).and_return(client)
      allow(client).to receive(:provision).and_return({ instance: broker_response_body, last_operation: create_last_operation })
      allow(client).to receive(:deprovision).and_return({ last_operation: delete_last_operation })
      allow(client).to receive(:fetch_service_instance_last_operation).and_return({ last_operation: { state: 'succeeded' } })

      allow(Jobs::Enqueuer).to receive(:new) do |job|
        enqueuer = FakeEnqueuer.new(job)
        @queue << enqueuer
        enqueuer
      end

      Delayed::Worker.delay_jobs = false
    end

    before do
      Thread.current[:thread_id] = 'test'
    end

    around do |example|
      Timeout.timeout(10) do
        example.run
      end
    end

    describe 'creating service' do
      let(:expected_race) {
        [
          Racecar::Turn.from('[test] service_broker_client.provision()'),
          Racecar::Turn.from('[test] service_instance.last_operation.{type = create, state = in progress}'),
          Racecar::Turn.from('[test] service_instance.create.enqueue()'),

          Racecar::Turn.from('[test] service_instance.get()'),
          Racecar::Turn.from('[test] service_broker_client.service_instance_last_operation()'),
          Racecar::Turn.from('[test] service_instance.lock()'),
          Racecar::Turn.from('[test] service_instance.last_operation.{state = succeeded}'),
          Racecar::Turn.from('[test] service_instance.last_operation.{changes = {}}'),
          Racecar::Turn.from('[test] service_instance.release()'),
        ]
      }

      it 'can call create service instance' do
        expect {
          create_action.create(request_attrs, true)
        }.to change { ServiceInstance.count }.from(1).to(2)

        service_instance = ServiceInstance.where(name: 'my-instance').first
        expect(service_instance).to be

        expect(@queue).to have(1).item
        expect(@queue.first.enqueued).to be(true)
        @queue.first.job.perform
      end
    end

    describe 'deleting service' do
      let(:expected_race) {
        [
          
        ]
      }

      it 'can call delete service instance' do
        expect {
          delete_action.delete([service_instance])

          expect(@queue).to have(1).item
          expect(@queue.first.enqueued).to be(true)
          @queue.first.job.perform
        }.to change { ServiceInstance.count }.from(1).to(0)
      end
    end
  end
end
