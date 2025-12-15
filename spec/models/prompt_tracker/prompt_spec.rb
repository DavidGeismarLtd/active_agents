# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe Prompt, type: :model do
    # Setup
    let(:valid_attributes) do
      {
        name: "test_prompt",
        description: "A test prompt",
        created_by: "test@example.com"
      }
    end

    # Validation Tests

    describe "validations" do
      it "is valid with valid attributes" do
        prompt = Prompt.new(valid_attributes)
        expect(prompt).to be_valid
      end

      it "requires name" do
        prompt = Prompt.new(valid_attributes.except(:name))
        expect(prompt).not_to be_valid
        expect(prompt.errors[:name]).to include("can't be blank")
      end

      it "requires unique name (case-insensitive)" do
        Prompt.create!(valid_attributes)
        duplicate = Prompt.new(valid_attributes)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include("has already been taken")
      end

      it "enforces name format with lowercase letters, numbers, and underscores only" do
        valid_names = [ "test", "test_prompt", "test123", "test_prompt_123" ]
        valid_names.each do |name|
          prompt = Prompt.new(valid_attributes.merge(name: name))
          expect(prompt).to be_valid, "Name '#{name}' should be valid"
        end

        invalid_names = [ "Test", "test-prompt", "test prompt", "test.prompt", "test@prompt" ]
        invalid_names.each do |name|
          prompt = Prompt.new(valid_attributes.merge(name: name))
          expect(prompt).not_to be_valid, "Name '#{name}' should be invalid"
          expect(prompt.errors[:name]).to include("must contain only lowercase letters, numbers, and underscores")
        end
      end
    end

    # Association Tests

    describe "associations" do
      let(:prompt) { Prompt.create!(valid_attributes) }

      it "has many prompt_versions" do
        expect(prompt).to respond_to(:prompt_versions)
        expect(prompt.prompt_versions.count).to eq(0)
      end

      it "destroys associated prompt_versions when destroyed" do
        version = prompt.prompt_versions.create!(
          user_prompt: "Hello {{name}}",
          version_number: 1,
          status: "active",
        )

        expect { prompt.destroy }.to change { PromptVersion.count }.by(-1)
      end

      it "has many ab_tests" do
        expect(prompt).to respond_to(:ab_tests)
      end

      it "has many llm_responses through prompt_versions" do
        expect(prompt).to respond_to(:llm_responses)
      end

      it "has many evaluations through llm_responses" do
        expect(prompt).to respond_to(:evaluations)
      end
    end

    # Scope Tests

    describe "scopes" do
      let!(:active_prompt) { Prompt.create!(valid_attributes) }
      let!(:archived_prompt) { Prompt.create!(valid_attributes.merge(name: "archived_prompt", archived_at: Time.current)) }

      describe ".active" do
        it "returns only non-archived prompts" do
          active_prompts = Prompt.active
          expect(active_prompts).to include(active_prompt)
          expect(active_prompts).not_to include(archived_prompt)
        end
      end

      describe ".archived" do
        it "returns only archived prompts" do
          archived_prompts = Prompt.archived
          expect(archived_prompts).to include(archived_prompt)
          expect(archived_prompts).not_to include(active_prompt)
        end
      end
    end

    # Instance Method Tests

    describe "instance methods" do
      let(:prompt) { Prompt.create!(valid_attributes) }

      describe "#active_version" do
        it "returns the active version" do
          active_version = prompt.prompt_versions.create!(
            user_prompt: "Active version",
            version_number: 2,
            status: "active",
          )
          deprecated_version = prompt.prompt_versions.create!(
            user_prompt: "Old version",
            version_number: 1,
            status: "deprecated",
          )

          expect(prompt.active_version).to eq(active_version)
        end

        it "returns nil when no active version exists" do
          expect(prompt.active_version).to be_nil
        end
      end

      describe "#latest_version" do
        it "returns most recently created version" do
          first_version = prompt.prompt_versions.create!(
            user_prompt: "First",
            version_number: 1,
            status: "deprecated",
          )
          sleep 0.01 # Ensure different timestamps
          latest_version = prompt.prompt_versions.create!(
            user_prompt: "Latest",
            version_number: 2,
            status: "active",
          )

          expect(prompt.latest_version).to eq(latest_version)
        end
      end

      describe "#archive!" do
        it "sets archived_at timestamp" do
          expect(prompt.archived_at).to be_nil

          prompt.archive!
          expect(prompt.reload.archived_at).not_to be_nil
        end

        it "deprecates all versions" do
          version = prompt.prompt_versions.create!(
            user_prompt: "Test",
            version_number: 1,
            status: "active",
          )

          prompt.archive!
          expect(version.reload.status).to eq("deprecated")
        end
      end

      describe "#unarchive!" do
        it "clears archived_at timestamp" do
          prompt.update!(archived_at: Time.current)
          expect(prompt.archived_at).not_to be_nil

          prompt.unarchive!
          expect(prompt.reload.archived_at).to be_nil
        end
      end

      describe "#archived?" do
        it "returns true when archived" do
          prompt.update!(archived_at: Time.current)
          expect(prompt.archived?).to be true
        end

        it "returns false when not archived" do
          expect(prompt.archived?).to be false
        end
      end

      describe "#total_llm_calls" do
        it "returns count of all responses across versions" do
          expect(prompt.total_llm_calls).to eq(0)

          # Create version and response
          version = prompt.prompt_versions.create!(
            user_prompt: "Test",
            version_number: 1,
            status: "active",
          )

          version.llm_responses.create!(
            rendered_prompt: "Test prompt",
            response_text: "Test response",
            model: "gpt-4",
            provider: "openai",
            status: "success"
          )

          expect(prompt.total_llm_calls).to eq(1)
        end
      end

      describe "#total_cost_usd" do
        it "returns 0 when no responses" do
          expect(prompt.total_cost_usd).to eq(0.0)
        end

        it "returns sum of costs across all responses" do
          version = prompt.prompt_versions.create!(
            user_prompt: "Test",
            version_number: 1,
            status: "active",
          )

          version.llm_responses.create!(
            rendered_prompt: "Test 1",
            response_text: "Response 1",
            model: "gpt-4",
            provider: "openai",
            status: "success",
            cost_usd: 0.05
          )

          version.llm_responses.create!(
            rendered_prompt: "Test 2",
            response_text: "Response 2",
            model: "gpt-4",
            provider: "openai",
            status: "success",
            cost_usd: 0.03
          )

          expect(prompt.total_cost_usd).to eq(0.08)
        end
      end

      describe "#average_response_time_ms" do
        it "returns nil when no responses" do
          expect(prompt.average_response_time_ms).to be_nil
        end

        it "returns average response time" do
          version = prompt.prompt_versions.create!(
            user_prompt: "Test",
            version_number: 1,
            status: "active",
          )

          version.llm_responses.create!(
            rendered_prompt: "Test 1",
            response_text: "Response 1",
            model: "gpt-4",
            provider: "openai",
            status: "success",
            response_time_ms: 100
          )

          version.llm_responses.create!(
            rendered_prompt: "Test 2",
            response_text: "Response 2",
            model: "gpt-4",
            provider: "openai",
            status: "success",
            response_time_ms: 200
          )

          expect(prompt.average_response_time_ms).to eq(150.0)
        end
      end

      describe "#active_evaluator_configs" do
        it "returns configs for the active version" do
          version = prompt.prompt_versions.create!(
            user_prompt: "Test",
            version_number: 1,
            status: "active",
          )

          config = version.evaluator_configs.create!(
            evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
            enabled: true,
            config: { min_length: 10, max_length: 100 }
          )

          expect(prompt.active_evaluator_configs).to include(config)
        end

        it "returns empty relation when no active version" do
          expect(prompt.active_evaluator_configs).to eq(EvaluatorConfig.none)
        end
      end
    end
  end
end
