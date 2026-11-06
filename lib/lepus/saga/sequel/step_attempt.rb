# frozen_string_literal: true

module Lepus
  module Saga
    module Sequel
      class StepAttempt < ::Sequel::Model(Lepus::Saga::Sequel.db[:saga_step_attempts])
        include StepAttemptBehaviour

        plugin Record, :context_after

        # The foreign key guards the reference; validating it would load the
        # execution again on every attempt the executor opens under the lock.
        many_to_one :execution, class: "Lepus::Saga::Sequel::Execution", key: :saga_execution_id

        dataset_module do
          order :chronological, :started_at, :created_at
        end

        def validate
          super
          validates_presence :step_name
          validates_includes STATUSES, :status
        end

        def before_validation
          self.status ||= "running"
          self.direction ||= "execute"
          self.epoch ||= 0
          self.context_after = {} if context_after.nil?
          super
        end
      end
    end
  end
end
