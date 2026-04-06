# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::AssistantChatbot::Assistants::TestRunnerWizardAssistant do
  describe "#system_prompt" do
    it "includes the prompt version id when present in context" do
      assistant = described_class.new(context: { agent_version_id: 27 })

      prompt = assistant.system_prompt

      expect(prompt).to include("AgentVersion #27")
      expect(prompt).to include("Test Runner Wizard Assistant")
    end

    it "mentions missing prompt version when not provided" do
      assistant = described_class.new(context: {})

      prompt = assistant.system_prompt

      expect(prompt).to include("AgentVersion is not explicitly specified")
    end

    it "describes the JSON plan format for run_tests" do
      assistant = described_class.new(context: { agent_version_id: 1 })

      prompt = assistant.system_prompt

      expect(prompt).to include("The JSON object MUST have this shape")
      expect(prompt).to include("\"agent_version_id\"")
      expect(prompt).to include("\"run_mode\"")
    end

    it "requires listing datasets before asking for a dataset id" do
      assistant = described_class.new(context: { agent_version_id: 1 })

      prompt = assistant.system_prompt

      expect(prompt).to include("MUST call the available_datasets_for_agent_version tool")
      expect(prompt).to include("Do NOT ask the user to type a dataset ID")
    end
  end
end
