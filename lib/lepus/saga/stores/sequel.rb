# frozen_string_literal: true

require "lepus/saga/sequel"

module Lepus
  module Saga
    module Stores
      # Executions and step attempts as Sequel models. Locks are
      # SELECT ... FOR UPDATE inside a transaction; on SQLite, where FOR UPDATE
      # does not exist, transactions open as IMMEDIATE, which serializes
      # writers on the whole database instead. Pass other model classes to use
      # subclasses with their own datasets.
      #
      # The query methods use portable SQL only (filters, GROUP BY, COUNT,
      # MAX), so they behave the same on SQLite, PostgreSQL and MySQL/MariaDB:
      # time buckets and percentiles are computed in Ruby over at most
      # `max_rows` selected values.
      class Sequel < Base
        def initialize(execution_class: nil, step_attempt_class: nil)
          super()
          @execution_class = execution_class
          @step_attempt_class = step_attempt_class
        end

        def execution_class
          @execution_class ||= Lepus::Saga::Sequel::Execution
        end

        def step_attempt_class
          @step_attempt_class ||= Lepus::Saga::Sequel::StepAttempt
        end

        def create_execution(attributes)
          execution_class.create(attributes)
        end

        def find_execution(id)
          execution_class[id]
        end

        def save_execution(execution)
          execution.save
          execution
        end

        def with_lock(execution)
          transaction do
            execution.lock!
            yield execution
          end
        end

        def with_locked_execution(id)
          transaction { yield execution_class.for_update.first(id: id) }
        end

        def increment_resume_count(execution)
          dataset = execution_class.where(id: execution.id)
          dataset.update(resume_count: ::Sequel[:resume_count] + 1, updated_at: Time.now.utc)
          execution.values[:resume_count] = dataset.get(:resume_count)
        end

        def stalled_executions(before:)
          execution_class.in_progress.where(::Sequel[:last_progress_at] < before).order(:last_progress_at, :id).all
        end

        def executions_for_resource(resource_type, resource_id)
          execution_class.for_resource(resource_type, resource_id).recent_first.all
        end

        def create_step_attempt(execution, attributes)
          step_attempt_class.create(attributes.merge(saga_execution_id: execution.id))
        rescue ::Sequel::UniqueConstraintViolation => error
          raise DuplicateAttemptError, error.message
        end

        def save_step_attempt(attempt)
          attempt.save
          attempt
        end

        def step_attempts(execution)
          attempts_of(execution).chronological.all
        end

        def executed_steps(executions)
          steps = executions.to_h { |execution| [execution.id, []] }
          return steps if steps.empty?

          step_attempt_class.where(saga_execution_id: steps.keys, direction: "execute").distinct
            .select_map(%i[saga_execution_id step_name]).each { |id, step| steps[id] << step }
          steps
        end

        def count_step_attempts(execution, step_name:, direction:, epoch:)
          attempts_of(execution).where(step_name: step_name, direction: direction, epoch: epoch).count
        end

        def running_step_attempt?(execution, step_name:, direction:, epoch:, started_since:)
          !attempts_of(execution)
            .where(step_name: step_name, direction: direction, epoch: epoch, status: "running")
            .where(::Sequel[:started_at] >= started_since)
            .empty?
        end

        def stale_step_attempts(execution, step_name:, direction:, epoch:, started_before:)
          attempts_of(execution)
            .where(step_name: step_name, direction: direction, epoch: epoch, status: "running")
            .where(::Sequel[:started_at] < started_before)
            .all
        end

        def step_succeeded?(execution, step_name)
          !attempts_of(execution).where(step_name: step_name, direction: "execute", status: "succeeded").empty?
        end

        def queries? = true

        # Keyset paging in up to two index-friendly queries: the executions
        # with a value in (value, id) order, then those without one by id.
        def list_executions(sort: :started_at, direction: :desc, after: nil, limit: 50, **filters)
          column, descending, nullable = list_order(sort, direction, filters)
          scope = matching_executions(**filters)
          order = ->(name) { descending ? ::Sequel.desc(name) : ::Sequel.asc(name) }
          if after
            cursor = execution_class.where(id: after).get([:id, column])
            return [] unless cursor
          end

          in_nulls = cursor && cursor.last.nil?
          rows = []
          unless in_nulls
            valued = nullable ? scope.exclude(column => nil) : scope
            valued = valued.where(beyond(column, after, descending)) if cursor
            rows = valued.order(order.call(column), order.call(:id)).limit(limit).all
          end
          return rows unless nullable && rows.size < limit

          unvalued = scope.where(column => nil)
          unvalued = unvalued.where(descending ? ::Sequel[:id] < after : ::Sequel[:id] > after) if in_nulls
          rows + unvalued.order(order.call(:id)).limit(limit - rows.size).all
        end

        def count_executions(group_by:, **filters)
          keys = group_keys(group_by)
          columns = keys.include?(:partition) ? keys | [:saga_name] : keys
          rows = matching_executions(**filters).group_and_count(*columns).naked.all
          tally_groups(rows.map { |row| [row.slice(*columns), row[:count]] }, group_by)
        end

        def execution_series(from:, to:, bucket:, saga_name: nil, max_rows: QUERY_MAX_ROWS)
          seconds = series_bucket(from, to, bucket)
          scope = matching_executions(saga_name: saga_name)
          started, started_truncated = take_rows(
            in_window(scope, :started_at, from, to)
              .order(::Sequel.desc(:started_at)).limit(max_rows + 1).select_map(:started_at),
            max_rows
          )
          finished, finished_truncated = take_rows(
            in_window(scope.where(status: ExecutionBehaviour::TERMINAL_STATUSES), :finished_at, from, to)
              .order(::Sequel.desc(:finished_at)).limit(max_rows + 1).select_map(%i[finished_at status]),
            max_rows
          )
          {rows: build_series(from, to, seconds, started, finished), truncated: started_truncated || finished_truncated}
        end

        def step_latency(from:, to:, saga_name: nil, max_rows: QUERY_MAX_ROWS)
          samples, truncated = take_rows(
            attempts_with_saga(from, to, saga_name)
              .where(attempts_table[:status] => LATENCY_STATUSES)
              .exclude(attempts_table[:duration_ms] => nil)
              .order(::Sequel.desc(attempts_table[:started_at])).limit(max_rows + 1)
              .select_map([executions_table[:saga_name], attempts_table[:step_name], attempts_table[:direction], attempts_table[:duration_ms]]),
            max_rows
          )
          {rows: latency_rows(samples), truncated: truncated}
        end

        def failure_summary(from:, to:, saga_name: nil, limit: 20)
          attempts = attempts_table
          saga = executions_table[:saga_name]
          count = ::Sequel.function(:count).*
          failed = attempts_with_saga(from, to, saga_name).where(attempts[:status] => "failed")
          failed
            .group(attempts[:error_class], saga, attempts[:step_name])
            .order(::Sequel.desc(count), ::Sequel.desc(::Sequel.function(:max, attempts[:finished_at])))
            .limit(limit)
            .select_map([
              attempts[:error_class], saga, attempts[:step_name], count.as(:count),
              ::Sequel.function(:count, attempts[:saga_execution_id]).distinct.as(:execution_count)
            ])
            .map do |error_class, group_saga, step_name, group_count, execution_count|
              message, last_seen_at, execution_id = failed
                .where(attempts[:error_class] => error_class, attempts[:step_name] => step_name, saga => group_saga)
                .order(::Sequel.desc(attempts[:finished_at]), ::Sequel.desc(attempts[:id]))
                .get([attempts[:error_message], attempts[:finished_at], attempts[:saga_execution_id]])
              {
                error_class: error_class, saga_name: group_saga, step_name: step_name, count: group_count.to_i,
                execution_count: execution_count.to_i, last_seen_at: last_seen_at, sample_message: message, sample_execution_id: execution_id
              }
            end
        end

        def saga_names
          execution_class.distinct.order(:saga_name).select_map(:saga_name)
        end

        private

        def db = execution_class.db

        # SQLite has no FOR UPDATE: an IMMEDIATE transaction takes the write
        # lock up front, so a second locker waits instead of reading alongside.
        # Sequel's SQLite adapter wraps an ArgumentError raised in the block in
        # Sequel::DatabaseError; the caller gets its own error back.
        def transaction(&)
          return db.transaction(&) unless db.database_type == :sqlite

          begin
            db.transaction(mode: :immediate, &)
          rescue ::Sequel::DatabaseError => error
            raise error unless error.wrapped_exception.is_a?(ArgumentError)

            raise error.wrapped_exception, cause: nil
          end
        end

        def attempts_of(execution)
          step_attempt_class.where(saga_execution_id: execution.id)
        end

        def executions_table = ::Sequel[execution_class.table_name]

        def attempts_table = ::Sequel[step_attempt_class.table_name]

        def in_window(scope, column, from, to)
          scope = scope.where(::Sequel[column] >= from) if from
          scope = scope.where(::Sequel[column] < to) if to
          scope
        end

        # Rows strictly after the execution `after` in (column, id) order,
        # comparing against its stored value in a subquery so no precision is
        # lost on the way through Ruby. The bare bound on the column lets the
        # (column, id) index start at the cursor instead of filtering every
        # row before it.
        def beyond(column, after, descending)
          value = execution_class.where(id: after).select(column)
          strict, bound = descending ? %i[< <=] : %i[> >=]
          compare = ->(operator, left, right) { ::Sequel::SQL::BooleanExpression.new(operator, left, right) }
          ::Sequel.&(
            compare.call(bound, ::Sequel[column], value),
            ::Sequel.|(compare.call(strict, ::Sequel[column], value), compare.call(strict, ::Sequel[:id], after))
          )
        end

        def matching_executions(saga_name: nil, status: nil, current_step: nil, partition: nil, resource: nil, from: nil, to: nil,
          progress_from: nil, progress_to: nil, finished_from: nil, finished_to: nil, error_class: nil, error_step: nil, error_from: nil,
          error_to: nil)
          sagas = filter_values(saga_name)
          statuses = filter_values(status)
          steps = filter_values(current_step)
          scope = execution_class.dataset
          scope = scope.where(saga_name: sagas) if sagas
          scope = scope.where(status: statuses) if statuses
          scope = scope.where(current_step: steps) if steps
          scope = in_window(scope, :started_at, from, to)
          scope = in_window(scope, :last_progress_at, progress_from, progress_to)
          scope = in_window(scope, :finished_at, finished_from, finished_to)
          failing = failed_attempts(filter_values(error_class), filter_values(error_step), error_from, error_to)
          scope = scope.where(id: failing.select(:saga_execution_id)) if failing
          scope = scope.where(in_partition(partition.to_s)) unless blank?(partition)
          scope = scope.where(matching_resource(scope, resource.to_s)) unless blank?(resource)
          scope
        end

        def failed_attempts(classes, steps, from, to)
          return if [classes, steps, from, to].all?(&:nil?)

          scope = step_attempt_class.where(status: "failed")
          scope = scope.where(error_class: classes) if classes
          scope = scope.where(step_name: steps) if steps
          in_window(scope, :started_at, from, to)
        end

        def in_partition(partition)
          ::Sequel.|({partition: partition}, {partition: nil, saga_name: partition_saga_names(partition)})
        end

        def matching_resource(scope, needle)
          pattern = "%#{scope.escape_like(needle)}%"
          ::Sequel.|(::Sequel.ilike(:resource_type, pattern), ::Sequel.ilike(:resource_id, pattern))
        end

        # Attempts started in the window, joined to their execution. Columns
        # are qualified from here on: both tables have id, status and the
        # timestamps.
        def attempts_with_saga(from, to, saga_name)
          scope = step_attempt_class.dataset
            .join(execution_class.table_name, id: :saga_execution_id)
            .where(attempts_table[:started_at] >= from)
            .where(attempts_table[:started_at] < to)
          sagas = filter_values(saga_name)
          sagas ? scope.where(executions_table[:saga_name] => sagas) : scope
        end

        def blank?(value) = value.to_s.strip.empty?
      end
    end
  end
end
