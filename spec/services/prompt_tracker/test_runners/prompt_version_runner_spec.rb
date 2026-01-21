# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    RSpec.describe PromptVersionRunner, type: :service do
      let(:prompt_version) { create(:prompt_version) }
      let(:test) { create(:test, testable: prompt_version) }

      let(:test_run) do
        create(:test_run,
               test: test,
               status: "running",
               metadata: metadata)
      end

      let(:runner) do
        described_class.new(
          test_run: test_run,
          test: test,
          testable: prompt_version,
          use_real_llm: false
        )
      end

      let(:metadata) { {} }

      describe "#conversational_mode? (private)" do
        subject(:conversational_mode?) { runner.send(:conversational_mode?) }

        context "when interlocutor_simulation_prompt is present in custom_variables" do
          let(:metadata) do
            {
              "custom_variables" => {
                "interlocutor_simulation_prompt" => "You are a simulated user."
              }
            }
          end

          it "returns true" do
            expect(conversational_mode?).to be true
          end
        end

        context "when interlocutor_simulation_prompt is blank" do
          let(:metadata) do
            {
              "custom_variables" => {
                "name" => "John"
              }
            }
          end

          it "returns false" do
            expect(conversational_mode?).to be false
          end
        end

        context "when custom_variables is not present" do
          let(:metadata) { {} }

          it "returns false" do
            expect(conversational_mode?).to be false
          end
        end
      end

      describe "#build_execution_params (private)" do
        subject(:execution_params) { runner.send(:build_execution_params) }

        context "when interlocutor_simulation_prompt is not present" do
          let(:metadata) do
            {
              "custom_variables" => { "name" => "John" }
            }
          end

          it "builds single-turn execution params" do
            expect(execution_params[:max_turns]).to eq(1)
            expect(execution_params[:interlocutor_prompt]).to be_nil
            expect(execution_params).not_to have_key(:mode)
          end
        end

        context "when interlocutor_simulation_prompt is present" do
          let(:metadata) do
            {
              "custom_variables" => {
                "name" => "John",
                "interlocutor_simulation_prompt" => "You are a simulated user.",
                "max_turns" => 7
              }
            }
          end

          it "builds conversational execution params" do
            expect(execution_params[:interlocutor_prompt]).to eq("You are a simulated user.")
            expect(execution_params[:max_turns]).to eq(7)
            expect(execution_params).not_to have_key(:mode)
          end
        end

        context "when interlocutor_simulation_prompt is present without max_turns" do
          let(:metadata) do
            {
              "custom_variables" => {
                "name" => "John",
                "interlocutor_simulation_prompt" => "Talk to the user."
              }
            }
          end

          it "defaults max_turns to 5" do
            expect(execution_params[:max_turns]).to eq(5)
          end
        end

        context "when interlocutor_simulation_prompt is blank" do
          let(:metadata) do
            {
              "custom_variables" => {
                "name" => "John",
                "interlocutor_simulation_prompt" => ""
              }
            }
          end

          it "builds single-turn params" do
            expect(execution_params[:max_turns]).to eq(1)
            expect(execution_params[:interlocutor_prompt]).to be_nil
          end
        end
      end
    end
  end
end
