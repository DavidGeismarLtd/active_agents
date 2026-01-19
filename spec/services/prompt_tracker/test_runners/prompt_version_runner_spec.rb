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

        context "when execution_mode metadata is 'conversation'" do
          let(:metadata) { { "execution_mode" => "conversation" } }

          it "returns true even if the test is single-turn" do
            allow(test).to receive(:conversational?).and_return(false)

            expect(conversational_mode?).to be true
          end
        end

        context "when execution_mode metadata is 'conversational'" do
          let(:metadata) { { "execution_mode" => "conversational" } }

          it "returns true" do
            allow(test).to receive(:conversational?).and_return(false)

            expect(conversational_mode?).to be true
          end
        end

        context "when execution_mode metadata is 'single'" do
          let(:metadata) { { "execution_mode" => "single" } }

          it "returns false even if the test is conversational" do
            allow(test).to receive(:conversational?).and_return(true)

            expect(conversational_mode?).to be false
          end
        end

        context "when execution_mode metadata is blank" do
          let(:metadata) { {} }

          it "delegates to test.conversational? when true" do
            allow(test).to receive(:conversational?).and_return(true)

            expect(conversational_mode?).to be true
          end

          it "delegates to test.conversational? when false" do
            allow(test).to receive(:conversational?).and_return(false)

            expect(conversational_mode?).to be false
          end
        end
      end

      describe "#build_execution_params (private)" do
        subject(:execution_params) { runner.send(:build_execution_params) }

        context "when execution_mode is 'single'" do
          let(:metadata) do
            {
              "execution_mode" => "single",
              "custom_variables" => { "name" => "John" }
            }
          end

          it "builds single-turn execution params" do
            expect(execution_params[:mode]).to eq(:single_turn)
            expect(execution_params[:max_turns]).to eq(1)
            expect(execution_params[:interlocutor_prompt]).to be_nil
          end
        end

        context "when execution_mode is 'conversation'" do
          let(:metadata) do
            {
              "execution_mode" => "conversation",
              "custom_variables" => {
                "name" => "John",
                "interlocutor_simulation_prompt" => "You are a simulated user.",
                "max_turns" => 7
              }
            }
          end

          it "builds conversational execution params" do
            expect(execution_params[:mode]).to eq(:conversational)
            expect(execution_params[:interlocutor_prompt]).to eq("You are a simulated user.")
            expect(execution_params[:max_turns]).to eq(7)
          end
        end

        context "when execution_mode is 'conversation' without max_turns" do
          let(:metadata) do
            {
              "execution_mode" => "conversation",
              "custom_variables" => {
                "name" => "John",
                "interlocutor_simulation_prompt" => "Talk to the user."
              }
            }
          end

          it "defaults max_turns to 5" do
            expect(execution_params[:mode]).to eq(:conversational)
            expect(execution_params[:max_turns]).to eq(5)
          end
        end

        context "when execution_mode is 'conversation' but interlocutor_simulation_prompt is missing" do
          let(:metadata) do
            {
              "execution_mode" => "conversation",
              "custom_variables" => {
                "name" => "John"
              }
            }
          end

          it "raises an informative error" do
            expect { execution_params }.to raise_error(ArgumentError, /interlocutor_simulation_prompt/)
          end
        end

        context "when execution_mode metadata is blank" do
          let(:metadata) do
            {
              "custom_variables" => {
                "name" => "John",
                "interlocutor_simulation_prompt" => "You are a simulated user.",
                "max_turns" => 3
              }
            }
          end

          it "uses single-turn params when test is single-turn" do
            allow(test).to receive(:conversational?).and_return(false)

            expect(execution_params[:mode]).to eq(:single_turn)
          end

          it "uses conversational params when test is conversational" do
            allow(test).to receive(:conversational?).and_return(true)

            expect(execution_params[:mode]).to eq(:conversational)
            expect(execution_params[:interlocutor_prompt]).to eq("You are a simulated user.")
          end
        end
      end
    end
  end
end
