# frozen_string_literal: true

RSpec.describe Lepus::Saga::Stores::Sequel do
  let(:store) { described_class.new }
  let(:execution_class) { Lepus::Saga::Sequel::Execution }

  def create_execution(resource_id: "1")
    store.create_execution(
      saga_name: "store.spec", resource_type: "Resource", resource_id: resource_id,
      current_step: "first", started_at: Time.now.utc, last_progress_at: Time.now.utc
    )
  end

  # Holds the execution's lock from another thread until the returned queue
  # receives a value.
  def hold_lock(execution)
    entered = Queue.new
    release = Queue.new
    holder = Thread.new do
      store.with_locked_execution(execution.id) do
        entered << true
        release.pop
      end
    end
    entered.pop
    [holder, release]
  end

  it_behaves_like "a lepus saga store"
  it_behaves_like "a lepus saga engine"
  it_behaves_like "a lepus saga query store"

  it "is selected by name" do
    config = Lepus::Saga::Configuration.new
    config.store = :sequel

    expect(config.store).to be_a(described_class)
  end

  it "returns the adapter's models" do
    execution = create_execution
    attempt = store.create_step_attempt(execution, step_name: "first", direction: "execute", epoch: 0, attempt: 1, started_at: Time.now.utc)

    expect(execution).to be_a(Lepus::Saga::Sequel::Execution)
    expect(attempt).to be_a(Lepus::Saga::Sequel::StepAttempt)
    expect(store.stalled_executions(before: Time.now.utc + 60)).to be_an(Array)
  end

  it "uses the model classes it is given" do
    execution_subclass = Class.new(execution_class)

    expect(described_class.new(execution_class: execution_subclass).create_execution(
      saga_name: "s", resource_type: "R", resource_id: "1", started_at: Time.now.utc
    )).to be_a(execution_subclass)
  end

  it "round-trips nested JSON context through the database" do
    context = {"order" => {"lines" => [{"sku" => "A-1", "qty" => 2}], "total" => 19.9, "gift" => false, "note" => nil}}
    execution = store.create_execution(
      saga_name: "s", resource_type: "R", resource_id: "1", started_at: Time.now.utc, context: context
    )

    expect(store.find_execution(execution.id).context).to eq(context)
    expect(JSON.parse(Database.db[:saga_executions].where(id: execution.id).get(:context).to_s)).to eq(context)
  end

  it "maps only unique violations to DuplicateAttemptError" do
    orphan = execution_class.new
    orphan.values[:id] = SecureRandom.uuid_v7

    expect {
      store.create_step_attempt(orphan, step_name: "first", direction: "execute", epoch: 0, attempt: 1, started_at: Time.now.utc)
    }.to raise_error(Sequel::ForeignKeyConstraintViolation)
  end

  it "raises validation errors for invalid executions" do
    expect { store.create_execution(saga_name: "", resource_type: "R", resource_id: "1", started_at: Time.now.utc) }
      .to raise_error(Sequel::ValidationFailed)
  end

  it "takes the lock with a single SELECT ... FOR UPDATE", :row_locks do
    execution = create_execution

    queries = Database.capture_sql { store.with_locked_execution(execution.id) { nil } }

    expect(queries.grep(/FOR UPDATE/).size).to eq(1)
  end

  it "makes a plain locking read from another connection wait for the lock" do
    execution = create_execution
    holder, release = hold_lock(execution)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    mode = Database.sqlite? ? {mode: :immediate} : {}
    reader = Thread.new { Database.db.transaction(**mode) { execution_class.for_update.first!(id: execution.id) } }
    sleep 0.3
    release << true
    [holder, reader].each(&:join)

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be >= 0.3
  end

  it "locks the execution's row, not the table", :row_locks do
    locked = create_execution(resource_id: "1")
    other = create_execution(resource_id: "2")
    holder, release = hold_lock(locked)

    result = Thread.new { store.with_locked_execution(other.id) { |execution| store.update_execution(execution, epoch: 1) } }
    finished = result.join(2)
    release << true
    holder.join

    expect(finished).not_to be_nil
    expect(store.find_execution(other.id).epoch).to eq(1)
  end
end
