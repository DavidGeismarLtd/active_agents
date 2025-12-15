# frozen_string_literal: true

require "ruby_llm/schema"

module PromptTracker
  # Factory for creating RubyLLM::Schema classes for LLM judge evaluations.
  #
  # This replaces the manual JSON Schema building with RubyLLM's elegant DSL.
  # All scores are always 0-100.
  #
  # @example Create a schema for evaluation
  #   schema = LlmJudgeSchema.simple_schema
  #
  #   chat = RubyLLM.chat(model: "gpt-4o").with_schema(schema)
  #   response = chat.ask("Evaluate this response...")
  #   response.content[:overall_score]  # => 85.0
  #   response.content[:feedback]  # => "The response is clear and accurate..."
  #
  class LlmJudgeSchema
    # Create a simple RubyLLM::Schema class for LLM judge evaluation
    # All scores are 0-100
    #
    # @return [Class] a RubyLLM::Schema subclass
    def self.simple_schema
      Class.new(RubyLLM::Schema) do
        # Overall score (0-100)
        number :overall_score,
               description: "Overall score from 0 to 100"

        # Feedback text
        string :feedback,
               description: "Detailed feedback explaining the score and evaluation"
      end
    end
  end
end
