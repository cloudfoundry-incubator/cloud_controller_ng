require 'spec_helper'
require 'actions/service_broker_create'

module VCAP
  module CloudController
    RSpec.describe 'ServiceBrokerCreate' do
      let(:dummy) { double('dummy').as_null_object }
      subject(:action) { V3::ServiceBrokerCreate.new(dummy, dummy) }

      let(:name) { "broker-name-#{Sham.sequence_id}" }
      let(:broker_url) { 'http://broker-url' }
      let(:auth_username) { 'username' }
      let(:auth_password) { 'password' }

      let(:message) do
        double('create broker message', {
          name: name,
          url: broker_url,
          credentials_data: double('credentials', {
            username: auth_username,
            password: auth_password
          }),
          relationships_message: double('relationships', {
            space_guid: nil
          })
        })
      end

      let(:message2) do
        double('create broker message 2', {
          name: "#{name}-2",
          url: broker_url + '2',
          credentials_data: double('credentials 2', {
            username: auth_username + '2',
            password: auth_password + '2'
          }),
          relationships_message: double('relationships 2', {
            space_guid: nil
          })
        })
      end

      let(:broker) { ServiceBroker.last }

      it 'creates a broker' do
        action.create(message)

        expect(broker.name).to eq(name)
        expect(broker.broker_url).to eq(broker_url)
        expect(broker.auth_username).to eq(auth_username)
        expect(broker.auth_password).to eq(auth_password)
        expect(broker.space_guid).to eq(nil)
      end

      it 'puts it in a SYNCHRONIZING state' do
        action.create(message)

        expect(broker.service_broker_state.state).to eq(ServiceBrokerStateEnum::SYNCHRONIZING)
      end

      before do
        ServiceBroker.db.transaction do
          ServiceBroker.all.each do |broker|
            puts broker.inspect
            broker.delete
          end
        end
      end

      describe 'concurrent behaviour' do
        let(:stepper) { Stepper.new }

        before do
          allow(ServiceBroker).to receive(:create).and_wrap_original do |m, params|
            stepper.step 'start create broker transaction'
            result = m.call(params)
            stepper.step 'finish create broker and start create broker state'
            result
          end

          allow(ServiceBrokerState).to receive(:create).and_wrap_original do |m, params|
            result = m.call(params)
            stepper.step 'finish create broker transaction'
            result
          end
        end

        def interleave_randomly(xs, ys)
          result = []
          while !xs.empty? && !ys.empty?
            choice = [xs, ys].sample
            result.push(choice.shift)
          end

          result.push(xs.shift) until xs.empty?
          result.push(ys.shift) until ys.empty?

          result
        end

        5.times do |i|
          it "interleave_randomly works okay #{i}" do
            result = interleave_randomly([
              '[1] start create broker transaction',
              '[1] finish create broker transaction',
              '[1] start create broker state transaction',
              '[1] finish create broker state transaction',
            ], [
              '[2] start create broker transaction',
              '[2] finish create broker transaction',
              '[2] start create broker state transaction',
              '[2] finish create broker state transaction',
            ])

            expect(result).to have(8).items
          end
        end

        20.times do |i|
          it "works when parallel brokers are created #{i}", isolation: :truncation do
            errors = []
            stepper.expected_order = interleave_randomly([
              '[1] start create broker transaction',
              '[1] finish create broker and start create broker state',
              '[1] finish create broker transaction',
            ], [
              '[2] start create broker transaction',
              '[2] finish create broker and start create broker state',
              '[2] finish create broker transaction',
            ])

            puts
            puts '===='
            puts stepper.expected_order
            puts '===='
            puts

            t1 = Thread.start do
              subject.create(message)
            rescue => e
              puts e
              stepper.abort!
              errors << e
            end
            t1.name = '1'

            t2 = Thread.start do
              subject.create(message2)
            rescue => e
              puts e
              stepper.abort!
              errors << e
            end
            t2.name = '2'

            t2.join
            t1.join

            expect(errors).to be_empty
          end
        end
      end
    end
  end
end

class Stepper
  MAX_RETRIES = 1000
  attr_accessor :expected_order, :aborted, :mutex

  def initialize
    @expected_order = []
    @aborted = false
    @mutex = Mutex.new
  end

  def step(message, &block)
    full_message = "[#{Thread.current.name}] #{message}"
    puts("expecting #{full_message}")

    retries = 0
    sleep(0.01) while top_expected_message != full_message && (retries += 1) < MAX_RETRIES && !aborted

    raise "Step #{full_message} has reached max #{retries} retries" if retries >= MAX_RETRIES

    raise 'Aborted' if aborted

    advance_to_next_message
    block.call if block

    puts("done #{full_message}")
  end

  def abort!
    self.aborted = true
  end

  private

  def top_expected_message
    mutex.lock
    result = expected_order.first
    mutex.unlock
    result
  end

  def advance_to_next_message
    mutex.lock
    expected_order.shift
    mutex.unlock
  end
end

class StockStepper
  def step(message, &block)
    block.call if block
  end
end
