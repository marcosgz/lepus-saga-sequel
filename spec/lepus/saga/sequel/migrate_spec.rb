# frozen_string_literal: true

RSpec.describe Lepus::Saga::Sequel, ".migrate" do
  let(:db) { Database.db }
  let(:indexes) do
    {
      saga_executions: %i[
        index_saga_executions_on_saga_name_and_created_at
        index_saga_executions_on_status_and_created_at
        index_saga_executions_on_finished_at
      ],
      saga_step_attempts: %i[
        index_saga_step_attempts_on_started_at
        index_saga_step_attempts_on_error_class_and_started_at
      ]
    }
  end

  def present_indexes
    indexes.to_h { |table, names| [table, names & db.indexes(table).keys] }
  end

  def version = db[described_class::MIGRATIONS_TABLE].get(:version)

  it "creates both tables with the columns the models read" do
    expect(db.schema(:saga_executions).map(&:first)).to match_array(
      Lepus::Saga::ExecutionBehaviour::ATTRIBUTES
    )
    expect(db.schema(:saga_step_attempts).map(&:first)).to match_array(
      Lepus::Saga::StepAttemptBehaviour::ATTRIBUTES
    )
  end

  it "stores the failure reason and error message as text" do
    expect(db.schema(:saga_executions).to_h[:failure_reason][:db_type]).to match(/text/i)
    expect(db.schema(:saga_step_attempts).to_h[:error_message][:db_type]).to match(/text/i)
  end

  it "has a unique attempt index and a foreign key to the execution" do
    expect(db.indexes(:saga_step_attempts)[:idx_saga_step_attempts_dedup]).to include(
      unique: true, columns: %i[saga_execution_id step_name direction epoch attempt]
    )
    expect(db.foreign_key_list(:saga_step_attempts)).to contain_exactly(
      include(columns: [:saga_execution_id], table: :saga_executions)
    )
  end

  it "records its version in its own table and runs once" do
    expect(version).to eq(2)
    expect { described_class.migrate(db) }.not_to(change { db.indexes(:saga_executions) })
    expect(version).to eq(2)
  end

  it "rolls the dashboard indexes back and forward" do
    expect(present_indexes).to eq(indexes)

    described_class.migrate(db, target: 1)
    expect(present_indexes).to eq(saga_executions: [], saga_step_attempts: [])

    described_class.migrate(db)
    expect(present_indexes).to eq(indexes)
  ensure
    described_class.migrate(db)
  end

  it "adds the dashboard indexes to tables created without them" do
    indexes.each { |table, names| names.each { |name| db.alter_table(table) { drop_index(nil, name: name) } } }
    db[described_class::MIGRATIONS_TABLE].update(version: 1)

    described_class.migrate(db)

    expect(present_indexes).to eq(indexes)
  ensure
    described_class.migrate(db)
  end

  it "drops and recreates the tables" do
    described_class.migrate(db, target: 0)
    expect(%i[saga_executions saga_step_attempts].map { |table| db.table_exists?(table) }).to eq([false, false])

    described_class.migrate(db)
    expect(%i[saga_executions saga_step_attempts].map { |table| db.table_exists?(table) }).to eq([true, true])
  ensure
    described_class.migrate(db)
  end
end
