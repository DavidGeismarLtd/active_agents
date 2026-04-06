# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::AssistantChatbot::Assistants::AgentCreationWizardAssistant do
  describe "#system_prompt" do
      it "reflects prompts list context when present" do
        assistant = described_class.new(context: { page_type: :agents_list })

      prompt = assistant.system_prompt

        expect(prompt).to include("Browsing agents list")
        expect(prompt).to include("Agent Creation Wizard Assistant")
    end

    it "mentions missing prompt context when not provided" do
      assistant = described_class.new(context: {})

      prompt = assistant.system_prompt

        expect(prompt).to include("Agent is not explicitly specified")
    end

        it "instructs the assistant to call create_prompt only after confirmation" do
          assistant = described_class.new(context: { page_type: :agents_list })

        prompt = assistant.system_prompt

        expect(prompt).to include("FINAL STEP")
        expect(prompt).to include("create_prompt")
        expect(prompt).to include("system_prompt_concept")
      end
  end
end
