# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::AssistantChatbot::Assistants::TestCreatorWizardAssistant do
  describe "#system_prompt" do
    it "includes the prompt version id when present in context" do
      assistant = described_class.new(context: { agent_version_id: 42 })

      prompt = assistant.system_prompt

      expect(prompt).to include("AgentVersion #42")
      expect(prompt).to include("Test Creator Wizard Assistant")
    end

    it "mentions missing prompt version when not provided" do
      assistant = described_class.new(context: {})

      prompt = assistant.system_prompt

      expect(prompt).to include("AgentVersion is not explicitly specified")
    end

    it "mentions the generate_tests tool" do
      assistant = described_class.new(context: { agent_version_id: 1 })

      prompt = assistant.system_prompt

      expect(prompt).to include("generate_tests")
    end

    it "does not mention run_tests or running tests" do
      assistant = described_class.new(context: { agent_version_id: 1 })

      prompt = assistant.system_prompt

      expect(prompt).not_to include("run_tests")
      expect(prompt).not_to include("run tests")
    end

    it "does not instruct calling get_agent_version_info" do
      assistant = described_class.new(context: { agent_version_id: 1 })

      prompt = assistant.system_prompt

      expect(prompt).not_to include("get_agent_version_info")
    end
  end

  describe "#allowed_tool_names" do
    it "only allows generate_tests" do
      assistant = described_class.new(context: {})

      expect(assistant.allowed_tool_names).to eq([ "generate_tests" ])
    end
  end
end
