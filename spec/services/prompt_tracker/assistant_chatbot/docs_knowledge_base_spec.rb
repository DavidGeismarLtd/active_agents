# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::AssistantChatbot::DocsKnowledgeBase do
  describe ".context_for" do
    it "always includes the available docs routes" do
      text = described_class.context_for("anything")

      expect(text).to include("/prompt_tracker/docs/tracking")
      expect(text).to include("/prompt_tracker/docs/testing_guide")
      expect(text).to include("/prompt_tracker/docs/playground_guide")
    end

    it "includes relevant excerpts when the query matches docs" do
      text = described_class.context_for("How do I run tests?")

      expect(text).to include("Relevant excerpts")
      expect(text).to include("/prompt_tracker/docs/testing_guide")
    end
  end
end
