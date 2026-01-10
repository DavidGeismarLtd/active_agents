# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # @deprecated Use SingleResponse::BaseSingleResponseEvaluator instead.
    #   This class is kept for backward compatibility only.
    #
    # Base class for evaluators that work with PromptVersion responses.
    # Now an alias for SingleResponse::BaseSingleResponseEvaluator.
    #
    # @see SingleResponse::BaseSingleResponseEvaluator
    BasePromptVersionEvaluator = SingleResponse::BaseSingleResponseEvaluator
  end
end
