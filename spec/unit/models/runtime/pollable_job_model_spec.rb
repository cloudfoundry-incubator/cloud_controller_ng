require 'spec_helper'

module VCAP::CloudController
  RSpec.describe PollableJobModel do
    describe('.find_by_delayed_job') do
      let(:delayed_job) { Delayed::Backend::Sequel::Job.create }
      let!(:pollable_job) { PollableJobModel.create(state: 'PROCESSING', delayed_job_guid: delayed_job.guid) }

      it 'returns the PollableJobModel for the given DelayedJob' do
        result = PollableJobModel.find_by_delayed_job(delayed_job)
        expect(result).to be_present
        expect(result).to eq(pollable_job)
      end
    end

    describe('.find_by_delayed_job_guid') do
      let(:delayed_job) { Delayed::Backend::Sequel::Job.create }
      let!(:pollable_job) { PollableJobModel.create(state: 'PROCESSING', delayed_job_guid: delayed_job.guid) }

      it 'returns the PollableJobModel for the given DelayedJob' do
        result = PollableJobModel.find_by_delayed_job_guid(delayed_job.guid)
        expect(result).to be_present
        expect(result).to eq(pollable_job)
      end
    end

    describe '#complete?' do
      context 'when the state is complete' do
        let(:job) { PollableJobModel.make(state: 'COMPLETE') }

        it 'returns true' do
          expect(job.complete?).to be(true)
        end
      end

      context 'when the state is not complete' do
        let(:failed_job) { PollableJobModel.make(state: 'FAILED') }
        let(:processing_job) { PollableJobModel.make(state: 'PROCESSING') }

        it 'returns false' do
          expect(failed_job.complete?).to be(false)
          expect(processing_job.complete?).to be(false)
        end
      end
    end

    describe '#resource_exists?' do
      it 'returns true if the resource exists' do
        app = AppModel.make
        job = PollableJobModel.make(resource_type: 'app', resource_guid: app.guid)
        expect(job.resource_exists?).to be(true)
      end

      it 'returns false if the resource does NOT exist' do
        job = PollableJobModel.make(resource_type: 'app', resource_guid: 'not-a-real-guid')
        expect(job.resource_exists?).to be(false)
      end
    end

    describe 'validations' do
      it 'validates warnings is an array' do
        job = PollableJobModel.make
        expect { job.update(warnings: 'something else') }.to raise_error(
          /warnings is not a valid array or nilclass/
        )
      end

      it 'validates each warning item to be a hash with a message' do
        job = PollableJobModel.make

        expect do
          job.update(warnings: [
            'not hash',
            { message: 'i am okay' },
            { message: {} },
            { 'message' => 'and me too' },
            { 'but i am' => 'wrong' }
          ])
        end.to raise_error(
          include(
            %{warnings should contain only hashes with a :message key, but found '"not hash"'},
            %{warnings[].message should be a string, but found '{}'},
            %{warnings should contain only hashes with a :message key, but found '{"but i am"=>"wrong"}'}
          )
        )
      end
    end
  end
end
