# frozen_string_literal: true

module PromptTracker
  # Execute user-written Ruby code using AWS Lambda.
  #
  # This service provides a simple interface for executing code in a sandboxed environment.
  # The actual execution is delegated to LambdaAdapter, which handles AWS Lambda integration.
  #
  # NOTE: Functions must be explicitly deployed to Lambda before execution.
  # Use FunctionDefinition#deploy to deploy, then call this method to execute.
  #
  # @example Execute a deployed function
  #   # First deploy the function
  #   function.deploy
  #
  #   # Then execute it
  #   result = CodeExecutor.execute(
  #     lambda_function_name: function.lambda_function_name,
  #     arguments: { name: "World" }
  #   )
  #   result.success? # => true
  #   result.result   # => { "greeting" => "Hello, World!" }
  #
  class CodeExecutor
    # Result object returned by execute.
    # @!attribute [r] success?
    #   @return [Boolean] whether execution succeeded
    # @!attribute [r] result
    #   @return [Hash, nil] execution result (if successful)
    # @!attribute [r] error
    #   @return [String, nil] error message (if failed)
    # @!attribute [r] execution_time_ms
    #   @return [Integer] execution time in milliseconds
    # @!attribute [r] logs
    #   @return [String] execution logs
    Result = Struct.new(:success?, :result, :error, :execution_time_ms, :logs, keyword_init: true)

    # Execute a deployed function on AWS Lambda.
    # NOTE: Function must already be deployed to Lambda!
    #
    # @param lambda_function_name [String] AWS Lambda function name
    # @param arguments [Hash] arguments to pass to the execute method
    # @return [Result] execution result
    def self.execute(lambda_function_name:, arguments:)
      LambdaAdapter.execute(
        lambda_function_name: lambda_function_name,
        arguments: arguments
      )
    end
  end
end
