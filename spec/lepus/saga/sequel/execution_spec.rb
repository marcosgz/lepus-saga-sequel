# frozen_string_literal: true

RSpec.describe Lepus::Saga::Sequel::Execution do
  include Lepus::Saga::ExampleHelpers

  def create_execution(**attributes)
    described_class.create({
      saga_name: "orders.checkout", resource_type: "Order", resource_id: "1",
      current_step: "first", started_at: Time.now.utc
    }.merge(attributes))
  end

  def create_attempt(execution, **attributes)
    Lepus::Saga::Sequel::StepAttempt.create({
      saga_execution_id: execution.id, step_name: "first", attempt: 1, started_at: Time.now.utc
    }.merge(attributes))
  end

  def ids(dataset) = dataset.select_map(:id)

  it "includes the execution behaviour" do
    expect(described_class.ancestors).to include(Lepus::Saga::ExecutionBehaviour)
    expect(described_class::STATUSES).to eq(Lepus::Saga::ExecutionBehaviour::STATUSES)
  end

  it "generates a uuid v7 id" do
    expect(create_execution.id).to match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/)
  end

  it "defaults context, progress clock and counters" do
    execution = create_execution.refresh

    expect(execution).to have_attributes(context: {}, status: "running", direction: "execute", epoch: 0, resume_count: 0)
    expect(execution.last_progress_at).to be_within(1).of(Time.now.utc)
  end

  it "validates presence, status and direction" do
    execution = described_class.new(status: "nope", direction: "sideways")

    expect(execution).not_to be_valid
    expect(execution.errors.keys).to include(:saga_name, :resource_type, :resource_id, :status, :direction)
  end

  it "stores a long failure reason" do
    execution = create_execution(failure_reason: "x" * 5000)

    expect(execution.refresh.failure_reason.size).to eq(5000)
  end

  it "keeps its column for a set partition and resolves a nil one to the definition's" do
    stub_const("OrdersCheckout", Class.new(Lepus::Saga::Definition) do
      saga_name "orders.checkout"
      partition "orders"

      step :first
    end)

    expect(create_execution.refresh.partition).to eq("orders")
    expect(create_execution(partition: "priority").refresh.partition).to eq("priority")
  end

  it "has read datasets" do
    completed = create_execution(status: "completed", resource_id: "2")
    running = create_execution(last_progress_at: ago(hours(1)))
    sleep 0.01
    compensating = create_execution(status: "compensating", direction: "compensate")

    expect(ids(described_class.for_resource("Order", 2))).to eq([completed.id])
    expect(ids(described_class.in_progress)).to contain_exactly(running.id, compensating.id)
    expect(ids(described_class.completed)).to eq([completed.id])
    expect(described_class.recent_first.first.id).to eq(compensating.id)
    expect(ids(described_class.stalled(minutes(15)))).to eq([running.id])
    expect(ids(described_class.stalled)).to eq([running.id])
  end

  it "deletes its step attempts with it" do
    execution = create_execution
    create_attempt(execution)

    expect { execution.destroy }.to change(Lepus::Saga::Sequel::StepAttempt, :count).by(-1)
  end

  describe ".prune" do
    def finished_execution(status: "completed", finished_at: ago(days(2)))
      create_execution(status: status, finished_at: finished_at).tap do |execution|
        create_attempt(execution, started_at: finished_at)
      end
    end

    it "deletes completed executions finished before the cutoff with their attempts" do
      old = Array.new(3) { finished_execution }
      recent = finished_execution(finished_at: ago(60))
      failed = finished_execution(status: "failed")
      running = create_execution

      expect(described_class.prune(finished_before: ago(days(1)), batch_size: 2)).to eq(3)
      expect(ids(described_class)).to contain_exactly(recent.id, failed.id, running.id)
      expect(Lepus::Saga::Sequel::StepAttempt.where(saga_execution_id: old.map(&:id)).count).to eq(0)
      expect(Lepus::Saga::Sequel::StepAttempt.count).to eq(2)
    end

    it "keeps what the calling dataset leaves out" do
      kept = finished_execution
      finished_execution

      expect(described_class.exclude(id: kept.id).prune(finished_before: ago(days(1)))).to eq(1)
      expect(ids(described_class)).to eq([kept.id])
    end
  end

  it "filters the attempts of the current step" do
    execution = create_execution
    current = create_attempt(execution)
    create_attempt(execution, epoch: 1)
    create_attempt(execution, step_name: "second")

    expect(ids(execution.attempts_for_current_step)).to eq([current.id])
  end
end
