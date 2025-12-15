# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe LlmJudgeSchema do
    describe ".simple_schema" do
      subject(:schema_class) { described_class.simple_schema }

      it "returns a RubyLLM::Schema subclass" do
        expect(schema_class).to be < RubyLLM::Schema
      end

      it "creates a valid schema class" do
        # The schema class should be a Class
        expect(schema_class).to be_a(Class)
        # It should inherit from RubyLLM::Schema
        expect(schema_class.ancestors).to include(RubyLLM::Schema)
      end

      it "creates a simple schema with overall_score and feedback" do
        # The schema should be valid and usable
        expect(schema_class).to be < RubyLLM::Schema
      end
    end
  end
end
