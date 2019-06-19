#require 'rubocop'
#require 'rubocop/rspec/support'
#
#RSpec.configure do |config|
#  config.include RuboCop::RSpec::ExpectOffense
#end

module RuboCop
  module Cop
    module CloudController
      class JobShouldNotAssignInstanceVarsOutsideInitialize < RuboCop::Cop::Cop
        MSG = 'Do not assign instance variables outside of initialize in delayed Jobs'.freeze

        def_node_matcher :instance_var_assignment?, <<-PATTERN
          (ivasgn ... (...))
        PATTERN

        def on_send(node)
          return if instance_var_assignment?(node)

          add_offense(node)
        end
      end
    end
  end
end

#describe RuboCop::Cop::CloudController::JobShouldNotAssignInstanceVarsOutsideInitialize do
#	let(:config) { RuboCop::Config.new }
#	subject(:cop) { described_class.new(config) }
#
#	it 'registers an offense when using `@something = whatever`' do
#		expect_offense(<<~RUBY)
#        @something = whatever
#                     ^^^^^^^^ Do not assign instance variables outside of initialize in delayed Jobs
#		RUBY
#	end
#end
