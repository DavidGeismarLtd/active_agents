# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # @deprecated Use Conversational::BaseAssistantsApiEvaluator instead.
    #   This class is kept for backward compatibility only.
    #
    # Base class for evaluators that work with OpenAI Assistant conversations.
    # Now an alias for Conversational::BaseAssistantsApiEvaluator.
    #
    # @see Conversational::BaseAssistantsApiEvaluator
    BaseOpenaiAssistantEvaluator = Conversational::BaseAssistantsApiEvaluator
  end
end
