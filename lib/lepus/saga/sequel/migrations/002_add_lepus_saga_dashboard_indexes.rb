# frozen_string_literal: true

# The indexes the query methods filter on, for tables created before 001
# declared them. A no-op on tables created by 001.
Sequel.migration do
  dashboard_indexes = {
    saga_executions: {
      index_saga_executions_on_saga_name_and_created_at: %i[saga_name created_at],
      index_saga_executions_on_status_and_created_at: %i[status created_at],
      index_saga_executions_on_finished_at: %i[finished_at]
    },
    saga_step_attempts: {
      index_saga_step_attempts_on_started_at: %i[started_at],
      index_saga_step_attempts_on_error_class_and_started_at: %i[error_class started_at]
    }
  }

  up do
    dashboard_indexes.each do |table, named|
      present = indexes(table).keys
      named.each { |name, columns| add_index(table, columns, name: name) unless present.include?(name) }
    end
  end

  down do
    dashboard_indexes.each do |table, named|
      present = indexes(table).keys
      named.each { |name, columns| drop_index(table, columns, name: name) if present.include?(name) }
    end
  end
end
