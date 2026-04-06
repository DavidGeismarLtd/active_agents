# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::AssistantChatbot::Assistants::DeploymentWizardAssistant do
  describe "#system_prompt" do
    it "includes the prompt version id when present in context" do
      assistant = described_class.new(context: { agent_version_id: 27 })

      prompt = assistant.system_prompt

      expect(prompt).to include("AgentVersion #27")
      expect(prompt).to include("Deployment Wizard Assistant")
    end

    it "mentions missing prompt version when not provided" do
      assistant = described_class.new(context: {})

      prompt = assistant.system_prompt

      expect(prompt).to include("AgentVersion is not explicitly specified")
    end

    it "describes the JSON plan format for deploy_agent" do
      assistant = described_class.new(context: { agent_version_id: 1 })

      prompt = assistant.system_prompt

      expect(prompt).to include("The JSON object MUST have this shape")
      expect(prompt).to include("\"agent_type\"")
      expect(prompt).to include("deploy_agent")
    end

      it "does not ask advanced conversational deployment questions" do
        assistant = described_class.new(context: { agent_version_id: 1 })

        prompt = assistant.system_prompt

        expect(prompt).not_to include("Ask how long conversations should be kept alive")
        expect(prompt).to include("Do NOT ask advanced config questions")
      end
  end
end
