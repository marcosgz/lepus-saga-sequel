# frozen_string_literal: true

RSpec.describe Lepus::Saga::Sequel, ".migrate" do
  let(:db) { Database.db }
  let(:execution_indexes) do
    {
      idx_saga_executions_on_resource: %i[resource_type resource_id started_at],
      index_saga_executions_on_started_at_and_id: %i[started_at id],
      index_saga_executions_on_duration_ms_and_id: %i[duration_ms id],
      index_saga_executions_on_finished_at: %i[finished_at],
      index_saga_executions_on_saga_name_and_started_at: %i[saga_name started_at],
      index_saga_executions_on_status_and_started_at: %i[status started_at],
      index_saga_executions_on_partition_and_started_at: %i[partition started_at]
    }
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
    expect(version).to eq(1)
    expect { described_class.migrate(db) }.not_to(change { db.indexes(:saga_executions) })
    expect(version).to eq(1)
  end

  it "indexes the columns the store sorts and filters executions on" do
    present = db.indexes(:saga_executions).transform_values { |index| index[:columns] }

    expect(present).to include(execution_indexes)
    expect(present.values.flatten).not_to include(:created_at)
    expect(db.indexes(:saga_step_attempts).transform_values { |index| index[:columns] }).to include(
      index_saga_step_attempts_on_started_at: %i[started_at],
      index_saga_step_attempts_on_error_class_and_started_at: %i[error_class started_at]
    )
  end

  it "stores the duration as a bigint" do
    expect(db.schema(:saga_executions).to_h[:duration_ms][:db_type]).to match(/bigint/i)
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
