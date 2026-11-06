# frozen_string_literal: true

Sequel.migration do
  up do
    create_table?(:saga_executions) do
      String :id, size: 36, primary_key: true
      String :saga_name, null: false
      String :resource_type, null: false
      String :resource_id, null: false
      String :status, null: false, default: "running"
      String :current_step
      String :direction, null: false, default: "execute"
      Integer :epoch, null: false, default: 0
      json :context, null: false
      String :correlation_id
      String :failure_reason, text: true
      String :partition
      DateTime :started_at, null: false
      DateTime :finished_at
      Bignum :duration_ms
      DateTime :last_progress_at, null: false
      Integer :resume_count, null: false, default: 0
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index %i[resource_type resource_id started_at], name: :idx_saga_executions_on_resource
      index %i[status updated_at], name: :index_saga_executions_on_status_and_updated_at
      index %i[status last_progress_at], name: :index_saga_executions_on_status_and_progress
      index %i[started_at id], name: :index_saga_executions_on_started_at_and_id
      index %i[duration_ms id], name: :index_saga_executions_on_duration_ms_and_id
      index :finished_at, name: :index_saga_executions_on_finished_at
      index %i[partition started_at], name: :index_saga_executions_on_partition_and_started_at
      index %i[saga_name started_at], name: :index_saga_executions_on_saga_name_and_started_at
      index %i[status started_at], name: :index_saga_executions_on_status_and_started_at
    end

    create_table?(:saga_step_attempts) do
      String :id, size: 36, primary_key: true
      foreign_key :saga_execution_id, :saga_executions, type: String, size: 36, null: false
      String :step_name, null: false
      String :direction, null: false, default: "execute"
      Integer :epoch, null: false, default: 0
      Integer :attempt, null: false
      String :status, null: false, default: "running"
      String :error_class
      String :error_message, text: true
      String :error_backtrace, text: true
      json :context_after, null: false
      DateTime :started_at, null: false
      DateTime :finished_at
      Float :duration_ms
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :saga_execution_id, name: :index_saga_step_attempts_on_saga_execution_id
      index %i[saga_execution_id step_name direction epoch attempt], unique: true, name: :idx_saga_step_attempts_dedup
      index :started_at, name: :index_saga_step_attempts_on_started_at
      index %i[error_class started_at], name: :index_saga_step_attempts_on_error_class_and_started_at
    end
  end

  down do
    drop_table?(:saga_step_attempts, :saga_executions)
  end
end
