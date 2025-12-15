# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe EvaluationHelpers do
    let(:prompt) do
      Prompt.create!(
        name: "test_prompt",
        description: "Test",
        category: "test"
      )
    end

    let(:version) do
      prompt.prompt_versions.create!(
        user_prompt: "Test",
        status: "active",
      )
    end

    describe ".normalize_score" do
      it "normalizes 0-100 score to 0-5" do
        expect(EvaluationHelpers.normalize_score(0, min: 0, max: 100, target_min: 0, target_max: 5)).to eq(0.0)
        expect(EvaluationHelpers.normalize_score(50, min: 0, max: 100, target_min: 0, target_max: 5)).to eq(2.5)
        expect(EvaluationHelpers.normalize_score(100, min: 0, max: 100, target_min: 0, target_max: 5)).to eq(5.0)
      end

      it "normalizes custom ranges" do
        expect(EvaluationHelpers.normalize_score(5, min: 0, max: 10, target_min: 0, target_max: 100)).to eq(50.0)
      end

      it "clamps values outside range" do
        expect(EvaluationHelpers.normalize_score(150, min: 0, max: 100, target_min: 0, target_max: 5)).to eq(5.0)
        expect(EvaluationHelpers.normalize_score(-10, min: 0, max: 100, target_min: 0, target_max: 5)).to eq(0.0)
      end

      it "handles same min and max" do
        expect(EvaluationHelpers.normalize_score(5, min: 5, max: 5, target_min: 0, target_max: 100)).to eq(0.0)
      end

      it "handles decimal scores" do
        result = EvaluationHelpers.normalize_score(75.5, min: 0, max: 100, target_min: 0, target_max: 10)
        expect(result).to be_within(0.01).of(7.55)
      end
    end

    describe ".average_score_for_version" do
      it "calculates average score normalized to 0-1" do
        response1 = version.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: "Response 1",
          status: "success"
        )
        response2 = version.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: "Response 2",
          status: "success"
        )

        response1.evaluations.create!(
          evaluator_type: "automated",
          evaluator_id: "test",
          score: 80,
          score_min: 0,
          score_max: 100
        )
        response2.evaluations.create!(
          evaluator_type: "automated",
          evaluator_id: "test",
          score: 60,
          score_min: 0,
          score_max: 100
        )

        avg = EvaluationHelpers.average_score_for_version(version)
        expect(avg).to eq(0.7) # (0.8 + 0.6) / 2 = 0.7
      end

      it "normalizes scores to 0-1 range" do
        response = version.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: "Response",
          status: "success"
        )

        response.evaluations.create!(
          evaluator_type: "automated",
          evaluator_id: "test",
          score: 3,
          score_min: 0,
          score_max: 5
        )

        avg = EvaluationHelpers.average_score_for_version(version)
        expect(avg).to eq(0.6) # 3/5 = 0.6
      end

      it "filters by evaluator type" do
        response = version.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: "Response",
          status: "success"
        )

        response.evaluations.create!(
          evaluator_type: "automated",
          evaluator_id: "test",
          score: 80,
          score_min: 0,
          score_max: 100
        )
        response.evaluations.create!(
          evaluator_type: "human",
          evaluator_id: "human",
          score: 40,
          score_min: 0,
          score_max: 100
        )

        avg = EvaluationHelpers.average_score_for_version(version, evaluator_type: "automated")
        expect(avg).to eq(0.8)
      end

      it "returns nil when no evaluations" do
        avg = EvaluationHelpers.average_score_for_version(version)
        expect(avg).to be_nil
      end

      it "returns nil when no responses" do
        empty_version = prompt.prompt_versions.create!(
          user_prompt: "Empty",
          status: "draft",
        )

        avg = EvaluationHelpers.average_score_for_version(empty_version)
        expect(avg).to be_nil
      end
    end

    describe ".average_score_for_response" do
      it "calculates average score for a response" do
        response = version.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: "Response",
          status: "success"
        )

        response.evaluations.create!(
          evaluator_type: "automated",
          evaluator_id: "test1",
          score: 80,
          score_min: 0,
          score_max: 100
        )
        response.evaluations.create!(
          evaluator_type: "automated",
          evaluator_id: "test2",
          score: 60,
          score_min: 0,
          score_max: 100
        )

        avg = EvaluationHelpers.average_score_for_response(response)
        expect(avg).to eq(0.7) # (0.8 + 0.6) / 2 = 0.7
      end
    end

    describe ".evaluation_statistics" do
      it "calculates statistics normalized to 0-1" do
        response = version.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: "Response",
          status: "success"
        )

        [ 60, 70, 80, 90, 100 ].each do |score|
          response.evaluations.create!(
            evaluator_type: "automated",
            evaluator_id: "test",
            score: score,
            score_min: 0,
            score_max: 100
          )
        end

        stats = EvaluationHelpers.evaluation_statistics(response.evaluations)
        expect(stats[:count]).to eq(5)
        expect(stats[:min]).to eq(0.6)
        expect(stats[:max]).to eq(1.0)
        expect(stats[:avg]).to eq(0.8)
        expect(stats[:median]).to eq(0.8)
      end

      it "calculates median for even count" do
        response = version.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: "Response",
          status: "success"
        )

        [ 60, 70, 80, 90 ].each do |score|
          response.evaluations.create!(
            evaluator_type: "automated",
            evaluator_id: "test",
            score: score,
            score_min: 0,
            score_max: 100
          )
        end

        stats = EvaluationHelpers.evaluation_statistics(response.evaluations)
        expect(stats[:median]).to eq(0.75)
      end

      it "returns nil for empty evaluations" do
        stats = EvaluationHelpers.evaluation_statistics(Evaluation.none)
        expect(stats).to be_nil
      end
    end

    describe ".compare_versions" do
      it "compares two versions" do
        version2 = prompt.prompt_versions.create!(
          user_prompt: "Test 2",
          status: "draft",
        )

        response1 = version.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: "Response 1",
          status: "success"
        )
        response1.evaluations.create!(
          evaluator_type: "automated",
          evaluator_id: "test",
          score: 80,
          score_min: 0,
          score_max: 100
        )

        response2 = version2.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: "Response 2",
          status: "success"
        )
        response2.evaluations.create!(
          evaluator_type: "automated",
          evaluator_id: "test",
          score: 60,
          score_min: 0,
          score_max: 100
        )

        comparison = EvaluationHelpers.compare_versions([ version, version2 ])
        expect(comparison[version.version_number]).to eq(0.8)
        expect(comparison[version2.version_number]).to eq(0.6)
      end
    end

    describe ".best_version" do
      it "finds the best version" do
        version2 = prompt.prompt_versions.create!(
          user_prompt: "Test 2",
          status: "draft",
        )

        response1 = version.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: "Response 1",
          status: "success"
        )
        response1.evaluations.create!(
          evaluator_type: "automated",
          evaluator_id: "test",
          score: 80,
          score_min: 0,
          score_max: 100
        )

        response2 = version2.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: "Response 2",
          status: "success"
        )
        response2.evaluations.create!(
          evaluator_type: "automated",
          evaluator_id: "test",
          score: 90,
          score_min: 0,
          score_max: 100
        )

        best = EvaluationHelpers.best_version([ version, version2 ])
        expect(best).to eq(version2)
      end

      it "returns nil when no evaluations" do
        version2 = prompt.prompt_versions.create!(
          user_prompt: "Test 2",
          status: "draft",
        )

        best = EvaluationHelpers.best_version([ version, version2 ])
        expect(best).to be_nil
      end
    end
  end
end
