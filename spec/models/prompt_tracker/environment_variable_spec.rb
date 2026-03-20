# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe EnvironmentVariable, type: :model do
    describe "validations" do
      it "requires name" do
        env_var = EnvironmentVariable.new(key: "API_KEY", value: "secret")
        expect(env_var).not_to be_valid
        expect(env_var.errors[:name]).to include("can't be blank")
      end

      it "requires key" do
        env_var = EnvironmentVariable.new(name: "API Key", value: "secret")
        expect(env_var).not_to be_valid
        expect(env_var.errors[:key]).to include("can't be blank")
      end

      it "requires value" do
        env_var = EnvironmentVariable.new(name: "API Key", key: "API_KEY")
        expect(env_var).not_to be_valid
        expect(env_var.errors[:value]).to include("can't be blank")
      end

      it "requires unique key" do
        EnvironmentVariable.create!(name: "First", key: "API_KEY", value: "secret1")
        duplicate = EnvironmentVariable.new(name: "Second", key: "API_KEY", value: "secret2")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:key]).to include("has already been taken")
      end

      it "requires uppercase key with underscores" do
        env_var = EnvironmentVariable.new(name: "API Key", key: "api-key", value: "secret")
        expect(env_var).not_to be_valid
        expect(env_var.errors[:key]).to include("must be uppercase with underscores (e.g., API_KEY)")
      end

      it "accepts valid uppercase key with underscores" do
        env_var = EnvironmentVariable.new(name: "API Key", key: "MY_API_KEY", value: "secret")
        expect(env_var).to be_valid
      end
    end

    describe "encryption" do
      it "encrypts the value" do
        env_var = EnvironmentVariable.create!(
          name: "Test Key",
          key: "TEST_KEY",
          value: "my_secret_value"
        )

        # The encrypted value in the database should be different from the plaintext
        raw_value = EnvironmentVariable.connection.select_value(
          "SELECT value FROM prompt_tracker_environment_variables WHERE id = #{env_var.id}"
        )

        expect(raw_value).not_to eq("my_secret_value")
        expect(env_var.value).to eq("my_secret_value")
      end
    end

    describe "associations" do
      it "has many function_definitions through join table" do
        env_var = EnvironmentVariable.create!(name: "API Key", key: "API_KEY", value: "secret")
        function = create(:function_definition)

        function.shared_environment_variables << env_var

        expect(env_var.function_definitions).to include(function)
        expect(function.shared_environment_variables).to include(env_var)
      end
    end

    describe "#display_name" do
      it "returns name with key in parentheses" do
        env_var = EnvironmentVariable.new(name: "OpenAI Key", key: "OPENAI_API_KEY", value: "secret")
        expect(env_var.display_name).to eq("OpenAI Key (OPENAI_API_KEY)")
      end
    end

    describe "#in_use?" do
      it "returns true when used by functions" do
        env_var = EnvironmentVariable.create!(name: "API Key", key: "API_KEY", value: "secret")
        function = create(:function_definition)
        function.shared_environment_variables << env_var

        expect(env_var.in_use?).to be true
      end

      it "returns false when not used" do
        env_var = EnvironmentVariable.create!(name: "API Key", key: "API_KEY", value: "secret")
        expect(env_var.in_use?).to be false
      end
    end

    describe "#usage_count" do
      it "returns count of functions using this variable" do
        env_var = EnvironmentVariable.create!(name: "API Key", key: "API_KEY", value: "secret")
        function1 = create(:function_definition, name: "func1")
        function2 = create(:function_definition, name: "func2")

        function1.shared_environment_variables << env_var
        function2.shared_environment_variables << env_var

        expect(env_var.usage_count).to eq(2)
      end
    end

    describe "scopes" do
      describe ".ordered_by_name" do
        it "orders by name" do
          env_var_b = EnvironmentVariable.create!(name: "B Key", key: "B_KEY", value: "secret")
          env_var_a = EnvironmentVariable.create!(name: "A Key", key: "A_KEY", value: "secret")

          expect(EnvironmentVariable.ordered_by_name.to_a).to eq([ env_var_a, env_var_b ])
        end
      end

      describe ".search" do
        it "searches by name, key, and description" do
          env_var1 = EnvironmentVariable.create!(name: "OpenAI Key", key: "OPENAI_KEY", value: "secret", description: "For AI")
          env_var2 = EnvironmentVariable.create!(name: "Stripe Key", key: "STRIPE_KEY", value: "secret", description: "For payments")

          expect(EnvironmentVariable.search("OpenAI")).to include(env_var1)
          expect(EnvironmentVariable.search("OpenAI")).not_to include(env_var2)
          expect(EnvironmentVariable.search("payments")).to include(env_var2)
        end
      end
    end
  end
end
