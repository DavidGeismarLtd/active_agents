# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # @deprecated Use Conversational::BaseConversationalEvaluator instead.
    #   This class is kept for backward compatibility only.
    #
    # Base class for evaluators that work with conversational data.
    # Now an alias for Conversational::BaseConversationalEvaluator.
    #
    # @see Conversational::BaseConversationalEvaluator
    BaseConversationalEvaluator = Conversational::BaseConversationalEvaluator
  end
end
