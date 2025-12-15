# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe AbTest, type: :model do
    # Setup
    let(:prompt) do
      Prompt.create!(
        name: "greeting",
        description: "Customer greeting prompt",
        category: "support",
        tags: [ "customer-facing", "support" ]
      )
    end

    let(:version_1) do
      prompt.prompt_versions.create!(
        user_prompt: "Hello {{name}}, how can I help you today?",
        version_number: 1,
        status: "active",
        variables_schema: [
          { "name" => "name", "type" => "string", "required" => true }
        ],
        model_config: {},
        notes: "Original version"
      )
    end

    let(:version_2) do
      prompt.prompt_versions.create!(
        user_prompt: "Hi {{name}}! Need help?",
        version_number: 2,
        status: "draft",
        variables_schema: [
          { "name" => "name", "type" => "string", "required" => true }
        ],
        model_config: {},
        notes: "Shorter version for testing"
      )
    end

    let(:valid_attributes) do
      {
        prompt: prompt,
        name: "Test A/B Test",
        description: "Testing shorter greeting",
        hypothesis: "Version 2 will reduce response time by 20%",
        metric_to_optimize: "response_time",
        optimization_direction: "minimize",
        traffic_split: { "A" => 50, "B" => 50 },
        variants: [
          { "name" => "A", "version_id" => version_1.id, "description" => "Current version" },
          { "name" => "B", "version_id" => version_2.id, "description" => "Shorter version" }
        ],
        confidence_level: 0.95,
        minimum_sample_size: 100
      }
    end

    # Validation Tests

    describe "validations" do
      it "is valid with valid attributes" do
        ab_test = AbTest.new(valid_attributes)
        expect(ab_test).to be_valid
      end

      it "requires name" do
        ab_test = AbTest.new(valid_attributes.except(:name))
        expect(ab_test).not_to be_valid
        expect(ab_test.errors[:name]).to include("can't be blank")
      end

      it "requires status" do
        ab_test = AbTest.new(valid_attributes.merge(status: nil))
        expect(ab_test).not_to be_valid
        expect(ab_test.errors[:status]).to include("can't be blank")
      end

      it "validates status inclusion" do
        AbTest::STATUSES.each do |status|
          ab_test = AbTest.new(valid_attributes.merge(status: status))
          expect(ab_test).to be_valid, "Status '#{status}' should be valid"
        end

        ab_test = AbTest.new(valid_attributes.merge(status: "invalid"))
        expect(ab_test).not_to be_valid
        expect(ab_test.errors[:status]).to include("is not included in the list")
      end

      it "requires metric_to_optimize" do
        ab_test = AbTest.new(valid_attributes.except(:metric_to_optimize))
        expect(ab_test).not_to be_valid
        expect(ab_test.errors[:metric_to_optimize]).to include("can't be blank")
      end

      it "validates metric_to_optimize inclusion" do
        AbTest::METRICS.each do |metric|
          ab_test = AbTest.new(valid_attributes.merge(metric_to_optimize: metric))
          expect(ab_test).to be_valid, "Metric '#{metric}' should be valid"
        end

        ab_test = AbTest.new(valid_attributes.merge(metric_to_optimize: "invalid"))
        expect(ab_test).not_to be_valid
      end

      it "requires optimization_direction" do
        ab_test = AbTest.new(valid_attributes.merge(optimization_direction: nil))
        expect(ab_test).not_to be_valid
      end

      it "validates optimization_direction inclusion" do
        %w[minimize maximize].each do |direction|
          ab_test = AbTest.new(valid_attributes.merge(optimization_direction: direction))
          expect(ab_test).to be_valid, "Direction '#{direction}' should be valid"
        end

        ab_test = AbTest.new(valid_attributes.merge(optimization_direction: "invalid"))
        expect(ab_test).not_to be_valid
      end

      it "requires traffic_split" do
        ab_test = AbTest.new(valid_attributes.merge(traffic_split: nil))
        expect(ab_test).not_to be_valid
      end

      it "validates traffic_split sums to 100" do
        ab_test = AbTest.new(valid_attributes.merge(traffic_split: { "A" => 50, "B" => 50 }))
        expect(ab_test).to be_valid

        ab_test = AbTest.new(valid_attributes.merge(traffic_split: { "A" => 60, "B" => 30 }))
        expect(ab_test).not_to be_valid
        expect(ab_test.errors[:traffic_split]).to include("percentages must sum to 100 (currently 90)")
      end

      it "requires variants" do
        ab_test = AbTest.new(valid_attributes.merge(variants: nil))
        expect(ab_test).not_to be_valid
      end

      it "validates variants structure" do
        ab_test = AbTest.new(valid_attributes)
        expect(ab_test).to be_valid

        # Missing name
        ab_test = AbTest.new(valid_attributes.merge(
          variants: [ { "version_id" => version_1.id } ]
        ))
        expect(ab_test).not_to be_valid

        # Missing version_id
        ab_test = AbTest.new(valid_attributes.merge(
          variants: [ { "name" => "A" } ]
        ))
        expect(ab_test).not_to be_valid
      end

      it "validates variants reference valid versions" do
        ab_test = AbTest.new(valid_attributes.merge(
          variants: [
            { "name" => "A", "version_id" => 99999, "description" => "Invalid" }
          ]
        ))
        expect(ab_test).not_to be_valid
        expect(ab_test.errors[:variants].first).to match(/non-existent version/)
      end

      it "does not allow duplicate variant names" do
        ab_test = AbTest.new(valid_attributes.merge(
          variants: [
            { "name" => "A", "version_id" => version_1.id },
            { "name" => "A", "version_id" => version_2.id }
          ]
        ))
        expect(ab_test).not_to be_valid
        expect(ab_test.errors[:variants].first).to match(/duplicate names/)
      end

      it "validates confidence_level range" do
        ab_test = AbTest.new(valid_attributes.merge(confidence_level: 0.95))
        expect(ab_test).to be_valid

        ab_test = AbTest.new(valid_attributes.merge(confidence_level: 0))
        expect(ab_test).not_to be_valid

        ab_test = AbTest.new(valid_attributes.merge(confidence_level: 1))
        expect(ab_test).not_to be_valid
      end

      it "validates minimum_sample_size is positive integer" do
        ab_test = AbTest.new(valid_attributes.merge(minimum_sample_size: 100))
        expect(ab_test).to be_valid

        ab_test = AbTest.new(valid_attributes.merge(minimum_sample_size: 0))
        expect(ab_test).not_to be_valid

        ab_test = AbTest.new(valid_attributes.merge(minimum_sample_size: -10))
        expect(ab_test).not_to be_valid
      end

      it "only allows one running test per prompt" do
        AbTest.create!(valid_attributes.merge(status: "running"))

        ab_test = AbTest.new(valid_attributes.merge(
          name: "Another test",
          status: "running"
        ))
        expect(ab_test).not_to be_valid
        expect(ab_test.errors[:base]).to include("Only one running test allowed per prompt")
      end

      it "allows multiple draft tests per prompt" do
        AbTest.create!(valid_attributes.merge(status: "draft"))
        ab_test = AbTest.new(valid_attributes.merge(name: "Another test", status: "draft"))
        expect(ab_test).to be_valid
      end
    end

    # Association Tests

    describe "associations" do
      it "belongs to prompt" do
        ab_test = AbTest.create!(valid_attributes)
        expect(ab_test.prompt).to eq(prompt)
      end

      it "has many llm_responses" do
        ab_test = AbTest.create!(valid_attributes)
        expect(ab_test).to respond_to(:llm_responses)
      end
    end

    # Scope Tests

    describe "scopes" do
      describe ".draft" do
        it "returns only draft tests" do
          draft = AbTest.create!(valid_attributes.merge(status: "draft"))
          running = AbTest.create!(valid_attributes.merge(name: "Running test", status: "running"))

          expect(AbTest.draft).to include(draft)
          expect(AbTest.draft).not_to include(running)
        end
      end

      describe ".running" do
        it "returns only running tests" do
          draft = AbTest.create!(valid_attributes.merge(status: "draft"))
          running = AbTest.create!(valid_attributes.merge(name: "Running test", status: "running"))

          expect(AbTest.running).to include(running)
          expect(AbTest.running).not_to include(draft)
        end
      end

      describe ".completed" do
        it "returns only completed tests" do
          completed = AbTest.create!(valid_attributes.merge(status: "completed"))
          running = AbTest.create!(valid_attributes.merge(name: "Running test", status: "running"))

          expect(AbTest.completed).to include(completed)
          expect(AbTest.completed).not_to include(running)
        end
      end

      describe ".for_prompt" do
        it "returns tests for specific prompt" do
          other_prompt = Prompt.create!(name: "other_prompt", description: "Other")
          other_version = other_prompt.prompt_versions.create!(
            user_prompt: "Other template",
            version_number: 1,
            status: "active",
          )

          test1 = AbTest.create!(valid_attributes)
          test2 = AbTest.create!(
            prompt: other_prompt,
            name: "Other test",
            description: "Testing other prompt",
            hypothesis: "Other hypothesis",
            metric_to_optimize: "response_time",
            optimization_direction: "minimize",
            traffic_split: { "A" => 100 },
            variants: [
              { "name" => "A", "version_id" => other_version.id, "description" => "Only version" }
            ],
            confidence_level: 0.95,
            minimum_sample_size: 100
          )

          expect(AbTest.for_prompt(prompt.id)).to include(test1)
          expect(AbTest.for_prompt(prompt.id)).not_to include(test2)
        end
      end
    end

    # State Management Tests

    describe "state management" do
      describe "#start!" do
        it "sets status to running and sets started_at" do
          ab_test = AbTest.create!(valid_attributes)
          expect(ab_test.started_at).to be_nil

          ab_test.start!

          expect(ab_test.status).to eq("running")
          expect(ab_test.started_at).not_to be_nil
        end
      end

      describe "#pause!" do
        it "sets status to paused" do
          ab_test = AbTest.create!(valid_attributes.merge(status: "running"))
          ab_test.pause!

          expect(ab_test.status).to eq("paused")
        end
      end

      describe "#resume!" do
        it "sets status back to running" do
          ab_test = AbTest.create!(valid_attributes.merge(status: "paused"))
          ab_test.resume!

          expect(ab_test.status).to eq("running")
        end
      end

      describe "#complete!" do
        it "sets status to completed and sets completed_at" do
          ab_test = AbTest.create!(valid_attributes.merge(status: "running"))
          ab_test.complete!(winner: "A")

          expect(ab_test.status).to eq("completed")
          expect(ab_test.completed_at).not_to be_nil
          expect(ab_test.results["winner"]).to eq("A")
        end
      end

      describe "#cancel!" do
        it "sets status to cancelled and sets cancelled_at" do
          ab_test = AbTest.create!(valid_attributes.merge(status: "running"))
          ab_test.cancel!

          expect(ab_test.status).to eq("cancelled")
          expect(ab_test.cancelled_at).not_to be_nil
        end
      end
    end

    # Variant Selection Tests

    describe "variant selection" do
      describe "#select_variant" do
        it "returns a variant name" do
          ab_test = AbTest.create!(valid_attributes)
          variant = ab_test.select_variant

          expect([ "A", "B" ]).to include(variant)
        end

        it "respects traffic split distribution" do
          ab_test = AbTest.create!(valid_attributes.merge(
            traffic_split: { "A" => 100, "B" => 0 }
          ))

          # Should always return A with 100% traffic
          10.times do
            expect(ab_test.select_variant).to eq("A")
          end
        end
      end

      describe "#version_for_variant" do
        it "returns correct version" do
          ab_test = AbTest.create!(valid_attributes)

          expect(ab_test.version_for_variant("A")).to eq(version_1)
          expect(ab_test.version_for_variant("B")).to eq(version_2)
        end

        it "returns nil for invalid variant" do
          ab_test = AbTest.create!(valid_attributes)

          expect(ab_test.version_for_variant("Z")).to be_nil
        end
      end

      describe "#variant_names" do
        it "returns all variant names" do
          ab_test = AbTest.create!(valid_attributes)

          expect(ab_test.variant_names).to eq([ "A", "B" ])
        end
      end
    end

    # Status Check Tests

    describe "status check methods" do
      it "#running? returns true when status is running" do
        ab_test = AbTest.create!(valid_attributes.merge(status: "running"))
        expect(ab_test.running?).to be true

        ab_test.update!(status: "draft")
        expect(ab_test.running?).to be false
      end

      it "#completed? returns true when status is completed" do
        ab_test = AbTest.create!(valid_attributes.merge(status: "completed"))
        expect(ab_test.completed?).to be true

        ab_test.update!(status: "running")
        expect(ab_test.completed?).to be false
      end

      it "#paused? returns true when status is paused" do
        ab_test = AbTest.create!(valid_attributes.merge(status: "paused"))
        expect(ab_test.paused?).to be true
      end

      it "#cancelled? returns true when status is cancelled" do
        ab_test = AbTest.create!(valid_attributes.merge(status: "cancelled"))
        expect(ab_test.cancelled?).to be true
      end

      it "#draft? returns true when status is draft" do
        ab_test = AbTest.create!(valid_attributes.merge(status: "draft"))
        expect(ab_test.draft?).to be true
      end
    end

    # Duration Tests

    describe "#duration_days" do
      it "returns nil if not started" do
        ab_test = AbTest.create!(valid_attributes)
        expect(ab_test.duration_days).to be_nil
      end

      it "calculates duration for running test" do
        ab_test = AbTest.create!(valid_attributes.merge(
          status: "running",
          started_at: 5.days.ago
        ))

        expect(ab_test.duration_days).to be_within(0.1).of(5.0)
      end

      it "uses completed_at for completed test" do
        ab_test = AbTest.create!(valid_attributes.merge(
          status: "completed",
          started_at: 10.days.ago,
          completed_at: 3.days.ago
        ))

        expect(ab_test.duration_days).to be_within(0.1).of(7.0)
      end
    end

    # Response Counting Tests

    describe "response counting" do
      describe "#total_responses" do
        it "returns count of all responses" do
          ab_test = AbTest.create!(valid_attributes.merge(status: "running"))
          expect(ab_test.total_responses).to eq(0)
        end
      end

      describe "#responses_for_variant" do
        it "returns count for specific variant" do
          ab_test = AbTest.create!(valid_attributes.merge(status: "running"))

          expect(ab_test.responses_for_variant("A")).to eq(0)
          expect(ab_test.responses_for_variant("B")).to eq(0)
        end
      end
    end

    # Winner Promotion Tests

    describe "#promote_winner!" do
      it "raises error if test not completed" do
        ab_test = AbTest.create!(valid_attributes.merge(status: "running"))

        expect do
          ab_test.promote_winner!
        end.to raise_error(StandardError, "Test must be completed")
      end

      it "raises error if no winner declared" do
        ab_test = AbTest.create!(valid_attributes.merge(
          status: "completed",
          results: {}
        ))

        expect do
          ab_test.promote_winner!
        end.to raise_error(StandardError, "No winner declared")
      end

      it "activates winning version" do
        ab_test = AbTest.create!(valid_attributes.merge(
          status: "completed",
          results: { "winner" => "B" }
        ))

        ab_test.promote_winner!

        version_2.reload
        expect(version_2.active?).to be true

        version_1.reload
        expect(version_1.deprecated?).to be true
      end
    end

    # Multi-variant Tests

    describe "multi-variant support" do
      it "supports more than 2 variants" do
        version_3 = prompt.prompt_versions.create!(
          user_prompt: "Version 3",
          version_number: 3,
          status: "draft",
        )

        ab_test = AbTest.new(valid_attributes.merge(
          traffic_split: { "A" => 33, "B" => 33, "C" => 34 },
          variants: [
            { "name" => "A", "version_id" => version_1.id },
            { "name" => "B", "version_id" => version_2.id },
            { "name" => "C", "version_id" => version_3.id }
          ]
        ))

        expect(ab_test).to be_valid
        expect(ab_test.variant_names.length).to eq(3)
      end

      it "supports uneven traffic splits" do
        ab_test = AbTest.new(valid_attributes.merge(
          traffic_split: { "A" => 80, "B" => 20 }
        ))

        expect(ab_test).to be_valid
      end
    end
  end
end
