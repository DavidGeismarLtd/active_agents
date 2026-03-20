# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_function_definitions
#
#  category              :string
#  code                  :text             not null
#  created_at            :datetime         not null
#  description           :text
#  enabled               :boolean          default(TRUE), not null
#  environment_variables :text
#  execution_count       :integer          default(0), not null
#  id                    :bigint           not null, primary key
#  language              :string           default("ruby"), not null
#  last_executed_at      :datetime
#  name                  :string           not null
#  parameters            :jsonb            not null
#  tags                  :jsonb
#  timeout_seconds       :integer          default(30), not null
#  updated_at            :datetime         not null
#
FactoryBot.define do
  factory :function_definition, class: "PromptTracker::FunctionDefinition" do
    sequence(:name) { |n| "test_function_#{n}" }
    description { "A test function that performs calculations" }
    language { "ruby" }
    category { "utility" }
    execution_count { 0 }
    tags { [ "test", "utility" ] }

    code do
      <<~RUBY
        def execute(args)
          operation = args[:operation] || args["operation"]
          a = args[:a] || args["a"]
          b = args[:b] || args["b"]

          result = case operation
          when "add" then a + b
          when "subtract" then a - b
          when "multiply" then a * b
          when "divide" then a / b
          else
            raise ArgumentError, "Unknown operation: \#{operation}"
          end

          { result: result }
        end
      RUBY
    end

    parameters do
      {
        "type" => "object",
        "properties" => {
          "operation" => {
            "type" => "string",
            "enum" => [ "add", "subtract", "multiply", "divide" ],
            "description" => "The arithmetic operation to perform"
          },
          "a" => {
            "type" => "number",
            "description" => "First operand"
          },
          "b" => {
            "type" => "number",
            "description" => "Second operand"
          }
        },
        "required" => [ "operation", "a", "b" ]
      }
    end

    environment_variables { {} }

    trait :with_env_vars do
      environment_variables do
        {
          "API_KEY" => "test_key_123",
          "API_URL" => "https://api.example.com"
        }
      end
    end

    trait :api_integration do
      category { "api" }
      code do
        <<~RUBY
          def execute(args)
            city = args[:city] || args["city"]
            api_key = ENV["OPENWEATHER_API_KEY"]

            # Mock API call
            { weather: "sunny", temperature: 72, city: city }
          end
        RUBY
      end

      parameters do
        {
          "type" => "object",
          "properties" => {
            "city" => {
              "type" => "string",
              "description" => "City name"
            }
          },
          "required" => [ "city" ]
        }
      end
    end

    trait :with_executions do
      after(:create) do |function|
        create_list(:function_execution, 5, function_definition: function)
      end
    end

    trait :deployed do
      deployment_status { "deployed" }
      lambda_function_name { "prompt_tracker_#{name}" }
      deployed_at { Time.current }
    end
  end
end
