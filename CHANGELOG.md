# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.3.0 - Unreleased
* Added: brand mark and README logo
* Added: `Lepus::Saga::Stores::Sequel`, selected with `Lepus::Saga.configure { |c| c.store = :sequel }`, and `Lepus::Saga::Sequel.db=` to bind the models to a database other than `Sequel::Model.db`
* Added: `Lepus::Saga::Sequel::Execution` and `StepAttempt` models (UUIDv7 ids, json context, read datasets) on the `saga_executions` and `saga_step_attempts` tables
* Added: `Lepus::Saga::Sequel.migrate(db)` runs the bundled migrations, tracked in `lepus_saga_schema_info`; the schema and index names match the lepus-saga-active_record install migration, `failure_reason` is `text` and there is no `lock_version` column
* Added: migration 002 adds the dashboard indexes to tables created without them
* Added: `Execution.prune(finished_before:)` deletes completed executions and their step attempts in batches
* Added: the optional query methods of the store contract (`list_executions`, `count_executions`, `execution_series`, `step_latency`, `failure_summary`, `saga_names`) in portable SQL, with time buckets and percentiles computed in Ruby over at most `max_rows` rows; `queries?` is true
* Added: SQLite locks open `IMMEDIATE` transactions, since SQLite has no `FOR UPDATE`
