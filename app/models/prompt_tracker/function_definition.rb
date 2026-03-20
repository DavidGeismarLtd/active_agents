# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_function_definitions
#
#  average_execution_time_ms :integer
#  category                  :string
#  code                      :text             not null
#  created_at                :datetime         not null
#  created_by                :string
#  dependencies              :jsonb
#  deployed_at               :datetime
#  deployment_error          :text
#  deployment_status         :string           default("not_deployed"), not null
#  description               :text
#  environment_variables     :text
#  example_input             :jsonb
#  example_output            :jsonb
#  execution_count           :integer          default(0), not null
#  id                        :bigint           not null, primary key
#  lambda_function_name      :string
#  language                  :string           default("ruby"), not null
#  last_executed_at          :datetime
#  name                      :string           not null
#  parameters                :jsonb            not null
#  tags                      :jsonb
#  updated_at                :datetime         not null
#  usage_count               :integer          default(0), not null
#  version                   :integer          default(1), not null
#
module PromptTracker
  # Represents a reusable executable function for agents.
  #
  # FunctionDefinitions store Ruby code that can be executed in a sandboxed
  # environment. They include:
  # - Code: Ruby source code with an execute method
  # - Parameters: JSON Schema defining expected arguments
  # - Environment Variables: Encrypted API keys and secrets
  # - Dependencies: Ruby gems required for execution
  #
  # @example Creating a weather function
  #   function = FunctionDefinition.create!(
  #     name: "get_weather",
  #     description: "Get current weather for a city",
  #     code: <<~RUBY,
  #       def execute(city:, units: "celsius")
  #         api_key = env['OPENWEATHER_API_KEY']
  #         response = HTTP.get("https://api.openweathermap.org/data/2.5/weather",
  #           params: { q: city, units: units, appid: api_key })
  #         JSON.parse(response.body)
  #       end
  #     RUBY
  #     parameters: {
  #       type: "object",
  #       properties: {
  #         city: { type: "string", description: "City name" },
  #         units: { type: "string", enum: ["celsius", "fahrenheit"] }
  #       },
  #       required: ["city"]
  #     },
  #     environment_variables: { "OPENWEATHER_API_KEY" => "sk_abc123" }
  #   )
  #
  # @example Testing a function
  #   result = function.test(city: "Berlin", units: "celsius")
  #   # => { success?: true, result: {...}, execution_time_ms: 234 }
  #
  class FunctionDefinition < ApplicationRecord
    # Associations
    has_many :function_executions,
             class_name: "PromptTracker::FunctionExecution",
             dependent: :destroy,
             inverse_of: :function_definition

    has_many :function_definition_environment_variables,
             class_name: "PromptTracker::FunctionDefinitionEnvironmentVariable",
             dependent: :destroy,
             inverse_of: :function_definition

    has_many :shared_environment_variables,
             through: :function_definition_environment_variables,
             source: :environment_variable,
             class_name: "PromptTracker::EnvironmentVariable"

    has_many :deployed_agent_functions,
             class_name: "PromptTracker::DeployedAgentFunction",
             dependent: :restrict_with_error,
             inverse_of: :function_definition

    has_many :deployed_agents,
             through: :deployed_agent_functions,
             class_name: "PromptTracker::DeployedAgent"

    # Validations
    validates :name, presence: true, uniqueness: true
    validates :code, presence: true
    validates :language, presence: true, inclusion: { in: %w[ruby] }
    validates :parameters, presence: true

    validate :parameters_must_be_valid_json_schema
    validate :code_must_be_valid_ruby

    # Encrypted attributes
    # Serialize as JSON to preserve Hash structure
    serialize :environment_variables, coder: JSON
    encrypts :environment_variables

    # Deployment statuses
    DEPLOYMENT_STATUSES = %w[not_deployed deploying deployed deployment_failed].freeze

    # Scopes
    scope :by_category, ->(category) { where(category: category) }
    scope :by_language, ->(language) { where(language: language) }
    scope :recently_executed, -> { where.not(last_executed_at: nil).order(last_executed_at: :desc) }
    scope :most_used, -> { where("execution_count > 0").order(execution_count: :desc) }
    scope :search, lambda { |query|
      where("name ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%")
    }
    scope :deployed, -> { where(deployment_status: "deployed") }
    scope :not_deployed, -> { where(deployment_status: "not_deployed") }
    scope :deployment_failed, -> { where(deployment_status: "deployment_failed") }

    # Test the function with sample input (does not track execution)
    # NOTE: Function must be deployed before testing!
    #
    # @param arguments [Hash] function arguments
    # @return [CodeExecutor::Result] execution result
    def test(arguments = {})
      CodeExecutor.execute(
        lambda_function_name: lambda_function_name,
        arguments: arguments
      )
    end

    # Execute the function and track the execution
    #
    # @param arguments [Hash] function arguments
    # @return [Hash] { success?: Boolean, result: Object, error: String, execution_time_ms: Integer }
    def execute(arguments)
      result = test(arguments)

      # Track execution
      function_executions.create!(
        arguments: arguments,
        result: result[:result],
        success: result[:success?],
        error_message: result[:error],
        execution_time_ms: result[:execution_time_ms],
        executed_at: Time.current
      )

      # Update stats
      increment!(:execution_count)
      update!(last_executed_at: Time.current)
      update_average_execution_time(result[:execution_time_ms])

      result
    end

    # Deployment status helpers
    def deployed?
      deployment_status == "deployed"
    end

    def not_deployed?
      deployment_status == "not_deployed"
    end

    def deploying?
      deployment_status == "deploying"
    end

    def deployment_failed?
      deployment_status == "deployment_failed"
    end

    def deployment_status_badge_class
      case deployment_status
      when "deployed" then "success"
      when "deploying" then "warning"
      when "deployment_failed" then "danger"
      else "secondary"
      end
    end

    def deployment_status_text
      case deployment_status
      when "deployed" then "✓ Deployed"
      when "deploying" then "⏳ Deploying..."
      when "deployment_failed" then "✗ Failed"
      else "Not Deployed"
      end
    end

    # Merge environment variables from both shared associations and inline JSON
    # Inline variables take precedence over shared ones
    # @return [Hash] merged environment variables
    def merged_environment_variables
      shared_vars = shared_environment_variables.each_with_object({}) do |env_var, hash|
        hash[env_var.key] = env_var.value
      end

      inline_vars = environment_variables || {}

      shared_vars.merge(inline_vars)
    end

    # Deploy the function to AWS Lambda
    #
    # @return [Boolean] true if deployment succeeded
    def deploy
      update!(deployment_status: "deploying", deployment_error: nil)

      result = CodeExecutor::LambdaAdapter.deploy(
        function_definition: self,
        code: code,
        environment_variables: merged_environment_variables,
        dependencies: dependencies || []
      )

      if result[:success]
        update!(
          deployment_status: "deployed",
          lambda_function_name: result[:function_name],
          deployed_at: Time.current,
          deployment_error: nil
        )
        true
      else
        update!(
          deployment_status: "deployment_failed",
          deployment_error: result[:error]
        )
        false
      end
    end

    # Remove the function from AWS Lambda
    #
    # @return [Boolean] true if undeployment succeeded
    def undeploy
      return true if not_deployed?

      result = CodeExecutor::LambdaAdapter.undeploy(lambda_function_name)

      if result[:success]
        update!(
          deployment_status: "not_deployed",
          lambda_function_name: nil,
          deployed_at: nil,
          deployment_error: nil
        )
        true
      else
        update!(deployment_error: result[:error])
        false
      end
    end

    private

    def parameters_must_be_valid_json_schema
      return if parameters.blank?

      unless parameters.is_a?(Hash)
        errors.add(:parameters, "must be a valid JSON object")
        return
      end

      # Basic JSON Schema validation
      unless parameters["type"] == "object"
        errors.add(:parameters, "must have type: 'object' at root level")
      end
    end

    def code_must_be_valid_ruby
      return if code.blank?

      # Basic Ruby syntax validation
      RubyVM::InstructionSequence.compile(code)
    rescue SyntaxError => e
      errors.add(:code, "contains syntax errors: #{e.message}")
    end

    def update_average_execution_time(new_time_ms)
      if average_execution_time_ms.nil?
        update!(average_execution_time_ms: new_time_ms)
      else
        # Rolling average
        new_avg = ((average_execution_time_ms * (execution_count - 1)) + new_time_ms) / execution_count
        update!(average_execution_time_ms: new_avg)
      end
    end
  end
end
