# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/schema"

RSpec.describe PromptTracker::LlmJudgeEvaluationJob, type: :job do
  include ActiveJob::TestHelper

  let(:prompt) { create(:prompt, :with_active_version) }
  let(:version) { prompt.active_version }
  let(:llm_response) { create(:llm_response, prompt_version: version) }
  let(:config) do
    {
      judge_model: "gpt-4o",
      custom_instructions: "Be strict in your evaluation. Consider accuracy, relevance, and clarity."
    }
  end

  # Mock RubyLLM responses
  let(:chat_double) { double("RubyLLM::Chat") }
  let(:schema_chat_double) { double("RubyLLM::Chat with schema") }
  let(:response_double) do
    double(
      "RubyLLM::Response",
      content: {
        overall_score: 85,
        feedback: "Good response with accurate information."
      },
      raw: double("raw response")
    )
  end

  before do
    allow(RubyLLM).to receive(:chat).and_return(chat_double)
    allow(chat_double).to receive(:with_schema).and_return(schema_chat_double)
    allow(schema_chat_double).to receive(:ask).and_return(response_double)
  end

  describe "#perform" do
    it "creates an evaluation for the response" do
      expect {
        described_class.new.perform(llm_response.id, config)
      }.to change(PromptTracker::Evaluation, :count).by(1)
    end

    it "uses the llm_judge evaluator" do
      allow(PromptTracker::EvaluatorRegistry).to receive(:build).and_call_original

      described_class.new.perform(llm_response.id, config)

      expect(PromptTracker::EvaluatorRegistry).to have_received(:build).with(
        :llm_judge,
        llm_response.response_text,
        hash_including(config.merge(llm_response: llm_response))
      )
    end

    it "stores the config in evaluation metadata" do
      described_class.new.perform(llm_response.id, config)

      evaluation = PromptTracker::Evaluation.last
      expect(evaluation.metadata["config"]).to eq(config.stringify_keys)
    end

    it "stores job execution info in metadata" do
      described_class.new.perform(llm_response.id, config)

      evaluation = PromptTracker::Evaluation.last
      expect(evaluation.metadata["manual_evaluation"]).to eq(true)
      expect(evaluation.metadata["executed_at"]).to be_present
    end

    it "generates a score within 0-100 range" do
      described_class.new.perform(llm_response.id, config)

      evaluation = PromptTracker::Evaluation.last
      expect(evaluation.score).to be >= 0
      expect(evaluation.score).to be <= 100
    end

    it "handles missing response gracefully" do
      expect {
        described_class.new.perform(999999, config)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "logs success message" do
      allow(Rails.logger).to receive(:info)

      described_class.new.perform(llm_response.id, config)

      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(/LLM Judge evaluation completed/)
      )
    end
  end

  describe "job queuing" do
    it "enqueues the job" do
      ActiveJob::Base.queue_adapter = :test

      expect {
        described_class.perform_later(llm_response.id, config)
      }.to have_enqueued_job(described_class).with(llm_response.id, config)
    end

    it "uses the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
