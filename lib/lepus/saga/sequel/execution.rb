# frozen_string_literal: true

module Lepus
  module Saga
    module Sequel
      class Execution < ::Sequel::Model(Lepus::Saga::Sequel.db[:saga_executions])
        include ExecutionBehaviour

        plugin Record, :context
        plugin :association_dependencies

        one_to_many :step_attempts, class: "Lepus::Saga::Sequel::StepAttempt", key: :saga_execution_id
        add_association_dependencies step_attempts: :delete

        dataset_module do
          where :in_progress, status: IN_PROGRESS_STATUSES
          where :completed, status: "completed"
          order :recent_first, ::Sequel.desc(:started_at), ::Sequel.desc(:id)

          def for_resource(type, id)
            where(resource_type: type, resource_id: id.to_s)
          end

          # Deliberately not `updated_at`: a re-publish, a lock or an attempt
          # opened and abandoned all touch the row while the cursor stands
          # still, so a wedged execution would keep resetting its own stall clock.
          def stalled(older_than = 15 * 60)
            in_progress.where(::Sequel[:last_progress_at] < Time.now.utc - older_than)
          end

          # Deletes completed executions that finished before the cutoff, with
          # their step attempts, batch by batch. Call it on a filtered dataset
          # to keep some: `exclude(id: ids_to_keep).prune(finished_before:)`.
          # Returns the number of executions deleted.
          def prune(finished_before:, batch_size: 1_000)
            step_attempt_class = model.association_reflection(:step_attempts).associated_class
            expired = completed.where(::Sequel[:finished_at] < finished_before)
            deleted = 0
            until (ids = expired.limit(batch_size).select_map(:id)).empty?
              db.transaction do
                step_attempt_class.where(saga_execution_id: ids).delete
                deleted += model.where(id: ids).delete
              end
            end
            deleted
          end
        end

        def attempts_for_current_step
          step_attempts_dataset.where(current_step_scope)
        end

        def validate
          super
          validates_presence %i[saga_name resource_type resource_id]
          validates_includes STATUSES, :status
          validates_includes DIRECTIONS, :direction
        end

        def before_validation
          self.status ||= "running"
          self.direction ||= "execute"
          self.epoch ||= 0
          self.resume_count ||= 0
          self.context = {} if context.nil?
          self.last_progress_at ||= Time.now.utc
          super
        end
      end
    end
  end
end
