# frozen_string_literal: true

RSpec.describe Lepus::Saga::Sequel::StepAttempt do
  include Lepus::Saga::ExampleHelpers

  let(:execution) do
    Lepus::Saga::Sequel::Execution.create(
      saga_name: "orders.checkout", resource_type: "Order", resource_id: "1",
      current_step: "first", started_at: Time.now.utc
    )
  end

  def create_attempt(**attributes)
    described_class.create({saga_execution_id: execution.id, step_name: "first", attempt: 1, started_at: Time.now.utc}.merge(attributes))
  end

  it "includes the step attempt behaviour" do
    expect(described_class.ancestors).to include(Lepus::Saga::StepAttemptBehaviour)
  end

  it "generates a uuid v7 id and defaults context_after" do
    attempt = create_attempt.refresh

    expect(attempt.id).to match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/)
    expect(attempt).to have_attributes(context_after: {}, status: "running", direction: "execute", epoch: 0)
    expect(attempt.execution.id).to eq(execution.id)
    expect(execution.step_attempts.map(&:id)).to eq([attempt.id])
  end

  it "validates step name and status" do
    attempt = described_class.new(status: "nope")

    expect(attempt).not_to be_valid
    expect(attempt.errors.keys).to contain_exactly(:step_name, :status)
  end

  it "orders chronologically" do
    later = create_attempt(step_name: "second", started_at: ago(minutes(1)))
    earlier = create_attempt(step_name: "first", started_at: ago(minutes(2)))

    expect(described_class.where(saga_execution_id: execution.id).chronological.select_map(:id)).to eq([earlier.id, later.id])
  end
end
