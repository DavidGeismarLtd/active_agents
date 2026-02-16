# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe PromptVersion, type: :model do
    # Setup
    let(:prompt) do
      Prompt.create!(
        name: "test_prompt",
        description: "A test prompt"
      )
    end

    let(:valid_attributes) do
      {
        prompt: prompt,
        user_prompt: "Hello {{name}}, how can I help with {{issue}}?",
        version_number: 1,
        status: "active",
        variables_schema: [
          { "name" => "name", "type" => "string", "required" => true },
          { "name" => "issue", "type" => "string", "required" => false }
        ],
        model_config: { "temperature" => 0.7, "max_tokens" => 150 }
      }
    end

    # Validation Tests

    describe "validations" do
      it "is valid with valid attributes" do
        version = PromptVersion.new(valid_attributes)
        expect(version).to be_valid
      end

      it "requires user_prompt" do
        version = PromptVersion.new(valid_attributes.except(:user_prompt))
        expect(version).not_to be_valid
        expect(version.errors[:user_prompt]).to include("can't be blank")
      end

      it "auto-sets version_number if not provided" do
        version = PromptVersion.new(valid_attributes.except(:version_number))
        expect(version).to be_valid
        version.save!
        expect(version.version_number).to eq(1)
      end

      it "requires positive version_number" do
        version = PromptVersion.new(valid_attributes.merge(version_number: 0))
        expect(version).not_to be_valid

        version = PromptVersion.new(valid_attributes.merge(version_number: -1))
        expect(version).not_to be_valid
      end

      it "requires unique version_number per prompt" do
        PromptVersion.create!(valid_attributes)
        duplicate = PromptVersion.new(valid_attributes)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:version_number]).to include("already exists for this prompt")
      end

      it "allows same version_number for different prompts" do
        PromptVersion.create!(valid_attributes)

        other_prompt = Prompt.create!(name: "other_prompt")
        other_version = PromptVersion.new(valid_attributes.merge(prompt: other_prompt))
        expect(other_version).to be_valid
      end

      it "requires valid status" do
        PromptVersion::STATUSES.each do |status|
          version = PromptVersion.new(valid_attributes.merge(status: status))
          expect(version).to be_valid, "Status '#{status}' should be valid"
        end

        version = PromptVersion.new(valid_attributes.merge(status: "invalid"))
        expect(version).not_to be_valid
        expect(version.errors[:status]).to include("is not included in the list")
      end



      it "validates variables_schema is an array" do
        version = PromptVersion.new(valid_attributes.merge(variables_schema: []))
        expect(version).to be_valid

        version = PromptVersion.new(valid_attributes.merge(variables_schema: "not an array"))
        expect(version).not_to be_valid
        expect(version.errors[:variables_schema]).to include("must be an array")
      end

      it "validates model_config is a hash" do
        version = PromptVersion.new(valid_attributes.merge(model_config: {}))
        expect(version).to be_valid

        version = PromptVersion.new(valid_attributes.merge(model_config: "not a hash"))
        expect(version).not_to be_valid
        expect(version.errors[:model_config]).to include("must be a hash")
      end

      describe "model_config tool_config validation" do
        it "allows model_config without tools" do
          version = PromptVersion.new(valid_attributes.merge(
                                        model_config: { "provider" => "openai", "model" => "gpt-4o" }
                                      ))
          expect(version).to be_valid
        end

        it "allows model_config with empty tools array" do
          version = PromptVersion.new(valid_attributes.merge(
                                        model_config: {
                                          "provider" => "openai",
                                          "model" => "gpt-4o",
                                          "tools" => [],
                                          "tool_config" => {}
                                        }
                                      ))
          expect(version).to be_valid
        end

        it "allows tools without tool_config (for tools that don't need config like code_interpreter)" do
          version = PromptVersion.new(valid_attributes.merge(
                                        model_config: {
                                          "provider" => "openai",
                                          "model" => "gpt-4o",
                                          "tools" => [ "code_interpreter" ],
                                          "tool_config" => {}
                                        }
                                      ))
          expect(version).to be_valid
        end

        it "allows tools array without tool_config key (normalizer will add it)" do
          version = PromptVersion.new(valid_attributes.merge(
                                        model_config: {
                                          "provider" => "openai",
                                          "model" => "gpt-4o",
                                          "tools" => [ "code_interpreter" ]
                                        }
                                      ))
          expect(version).to be_valid
        end

        it "validates tool_config is a hash" do
          version = PromptVersion.new(valid_attributes.merge(
                                        model_config: {
                                          "provider" => "openai",
                                          "model" => "gpt-4o",
                                          "tools" => [ "file_search" ],
                                          "tool_config" => "not a hash"
                                        }
                                      ))
          expect(version).not_to be_valid
          expect(version.errors[:model_config]).to include("tool_config must be a hash")
        end

        it "validates file_search config structure" do
          version = PromptVersion.new(valid_attributes.merge(
                                        model_config: {
                                          "provider" => "openai",
                                          "model" => "gpt-4o",
                                          "tools" => [ "file_search" ],
                                          "tool_config" => {
                                            "file_search" => "not a hash"
                                          }
                                        }
                                      ))
          expect(version).not_to be_valid
          expect(version.errors[:model_config]).to include("tool_config.file_search must be a hash")
        end

        it "validates vector_store_ids is an array" do
          version = PromptVersion.new(valid_attributes.merge(
                                        model_config: {
                                          "provider" => "openai",
                                          "model" => "gpt-4o",
                                          "tools" => [ "file_search" ],
                                          "tool_config" => {
                                            "file_search" => {
                                              "vector_store_ids" => "not an array"
                                            }
                                          }
                                        }
                                      ))
          expect(version).not_to be_valid
          expect(version.errors[:model_config]).to include("tool_config.file_search.vector_store_ids must be an array")
        end

        it "allows valid file_search config with vector_store_ids" do
          version = PromptVersion.new(valid_attributes.merge(
                                        model_config: {
                                          "provider" => "openai",
                                          "model" => "gpt-4o",
                                          "tools" => [ "file_search" ],
                                          "tool_config" => {
                                            "file_search" => {
                                              "vector_store_ids" => [ "vs_123", "vs_456" ]
                                            }
                                          }
                                        }
                                      ))
          expect(version).to be_valid
        end

        it "validates functions config is an array" do
          version = PromptVersion.new(valid_attributes.merge(
                                        model_config: {
                                          "provider" => "openai",
                                          "model" => "gpt-4o",
                                          "tools" => [ "functions" ],
                                          "tool_config" => {
                                            "functions" => "not an array"
                                          }
                                        }
                                      ))
          expect(version).not_to be_valid
          expect(version.errors[:model_config]).to include("tool_config.functions must be an array")
        end

        it "allows valid functions config" do
          version = PromptVersion.new(valid_attributes.merge(
                                        model_config: {
                                          "provider" => "openai",
                                          "model" => "gpt-4o",
                                          "tools" => [ "functions" ],
                                          "tool_config" => {
                                            "functions" => [
                                              { "name" => "get_weather", "parameters" => {} }
                                            ]
                                          }
                                        }
                                      ))
          expect(version).to be_valid
        end
      end

      describe "response_schema validation" do
        it "allows nil response_schema" do
          version = PromptVersion.new(valid_attributes.merge(response_schema: nil))
          expect(version).to be_valid
        end

        it "requires response_schema to be a hash" do
          version = PromptVersion.new(valid_attributes.merge(response_schema: "not a hash"))
          expect(version).not_to be_valid
          expect(version.errors[:response_schema]).to include("must be a valid JSON Schema (Hash)")
        end

        it "requires response_schema to have a type property" do
          version = PromptVersion.new(valid_attributes.merge(response_schema: { "properties" => {} }))
          expect(version).not_to be_valid
          expect(version.errors[:response_schema]).to include("must have a 'type' property")
        end

        it "requires object type to have properties" do
          version = PromptVersion.new(valid_attributes.merge(response_schema: { "type" => "object" }))
          expect(version).not_to be_valid
          expect(version.errors[:response_schema]).to include("must have 'properties' when type is 'object'")
        end

        it "accepts valid JSON Schema with object type" do
          schema = {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string" }
            },
            "required" => [ "name" ]
          }
          version = PromptVersion.new(valid_attributes.merge(response_schema: schema))
          expect(version).to be_valid
        end

        it "accepts valid JSON Schema with non-object type" do
          schema = { "type" => "string" }
          version = PromptVersion.new(valid_attributes.merge(response_schema: schema))
          expect(version).to be_valid
        end
      end

      it "allows user_prompt changes when no responses exist" do
        version = PromptVersion.create!(valid_attributes)
        version.user_prompt = "New template"
        expect(version).to be_valid
        expect(version.save).to be true
      end

      it "prevents user_prompt changes when responses exist" do
        version = PromptVersion.create!(valid_attributes)
        version.llm_responses.create!(
          rendered_prompt: "Test",
          response_text: "Response",
          model: "gpt-4",
          provider: "openai",
          status: "success"
        )

        version.user_prompt = "New template"
        expect(version).not_to be_valid
        expect(version.errors[:user_prompt]).to include("cannot be changed after responses exist")
      end
    end

    # Callback Tests

    describe "callbacks" do
      it "auto-increments version_number when not provided" do
        version1 = PromptVersion.create!(valid_attributes.except(:version_number))
        expect(version1.version_number).to eq(1)

        version2 = PromptVersion.create!(valid_attributes.except(:version_number))
        expect(version2.version_number).to eq(2)

        version3 = PromptVersion.create!(valid_attributes.except(:version_number))
        expect(version3.version_number).to eq(3)
      end

      describe "auto-extracting variables_schema" do
        it "extracts variables from user_prompt when variables_schema is not provided" do
          version = PromptVersion.create!(
            valid_attributes.except(:variables_schema).merge(
              user_prompt: "Hello {{name}}, how can I help with {{issue}}?"
            )
          )

          expect(version.variables_schema).to be_present
          expect(version.variables_schema.length).to eq(2)

          name_var = version.variables_schema.find { |v| v["name"] == "name" }
          expect(name_var).to be_present
          expect(name_var["type"]).to eq("string")
          expect(name_var["required"]).to eq(false)

          issue_var = version.variables_schema.find { |v| v["name"] == "issue" }
          expect(issue_var).to be_present
          expect(issue_var["type"]).to eq("string")
          expect(issue_var["required"]).to eq(false)
        end

        it "extracts single variable from user_prompt" do
          version = PromptVersion.create!(
            valid_attributes.except(:variables_schema).merge(
              user_prompt: "tell me everything you know about {{historical_event}}"
            )
          )

          expect(version.variables_schema).to be_present
          expect(version.variables_schema.length).to eq(1)
          expect(version.variables_schema.first["name"]).to eq("historical_event")
          expect(version.variables_schema.first["type"]).to eq("string")
          expect(version.variables_schema.first["required"]).to eq(false)
        end

        it "extracts variables with Liquid filters" do
          version = PromptVersion.create!(
            valid_attributes.except(:variables_schema).merge(
              user_prompt: "Hello {{ name | upcase }}, welcome!"
            )
          )

          expect(version.variables_schema).to be_present
          expect(version.variables_schema.length).to eq(1)
          expect(version.variables_schema.first["name"]).to eq("name")
        end

        it "extracts variables from Liquid conditionals" do
          version = PromptVersion.create!(
            valid_attributes.except(:variables_schema).merge(
              user_prompt: "{% if premium %}Premium content{% endif %}"
            )
          )

          expect(version.variables_schema).to be_present
          expect(version.variables_schema.length).to eq(1)
          expect(version.variables_schema.first["name"]).to eq("premium")
        end

        it "extracts variables from Liquid loops" do
          version = PromptVersion.create!(
            valid_attributes.except(:variables_schema).merge(
              user_prompt: "{% for product in products %}Product: {{ product.name }}{% endfor %}"
            )
          )

          expect(version.variables_schema).to be_present
          # Extracts both 'products' (the collection) and 'product' (the loop variable reference)
          expect(version.variables_schema.length).to eq(2)
          expect(version.variables_schema.map { |v| v["name"] }).to include("products", "product")
        end

        it "extracts multiple variables and removes duplicates" do
          version = PromptVersion.create!(
            valid_attributes.except(:variables_schema).merge(
              user_prompt: "{{name}} and {{name}} and {{age}}"
            )
          )

          expect(version.variables_schema).to be_present
          expect(version.variables_schema.length).to eq(2)
          expect(version.variables_schema.map { |v| v["name"] }).to match_array(%w[name age])
        end

        it "does not extract variables when variables_schema is explicitly provided" do
          custom_schema = [
            { "name" => "custom_var", "type" => "integer", "required" => true }
          ]

          version = PromptVersion.create!(
            valid_attributes.merge(
              user_prompt: "Hello {{name}}",
              variables_schema: custom_schema
            )
          )

          # Should keep the explicitly provided schema
          expect(version.variables_schema).to eq(custom_schema)
          expect(version.variables_schema.first["name"]).to eq("custom_var")
        end

        it "does not extract variables when user_prompt has no variables" do
          version = PromptVersion.create!(
            valid_attributes.except(:variables_schema).merge(
              user_prompt: "This is a static template with no variables"
            )
          )

          expect(version.variables_schema).to be_blank
        end

        it "extracts variables on update when user_prompt changes and schema is blank" do
          version = PromptVersion.create!(
            valid_attributes.except(:variables_schema).merge(
              user_prompt: "Original template"
            )
          )

          expect(version.variables_schema).to be_blank

          version.update!(user_prompt: "Updated {{template}} with {{variables}}")

          expect(version.variables_schema).to be_present
          expect(version.variables_schema.length).to eq(2)
          expect(version.variables_schema.map { |v| v["name"] }).to match_array(%w[template variables])
        end

        it "does not override existing variables_schema on update" do
          version = PromptVersion.create!(valid_attributes)
          original_schema = version.variables_schema.dup

          version.update!(notes: "Updated notes")

          expect(version.variables_schema).to eq(original_schema)
        end

        it "sorts variables alphabetically" do
          version = PromptVersion.create!(
            valid_attributes.except(:variables_schema).merge(
              user_prompt: "{{zebra}} {{apple}} {{banana}}"
            )
          )

          expect(version.variables_schema.map { |v| v["name"] }).to eq(%w[apple banana zebra])
        end
      end
    end

    # Scope Tests

    describe "scopes" do
      describe ".active" do
        it "returns only active versions" do
          active = PromptVersion.create!(valid_attributes.merge(status: "active"))
          deprecated = PromptVersion.create!(valid_attributes.merge(version_number: 2, status: "deprecated"))

          active_versions = PromptVersion.active
          expect(active_versions).to include(active)
          expect(active_versions).not_to include(deprecated)
        end
      end

      describe ".deprecated" do
        it "returns only deprecated versions" do
          active = PromptVersion.create!(valid_attributes.merge(status: "active"))
          deprecated = PromptVersion.create!(valid_attributes.merge(version_number: 2, status: "deprecated"))

          deprecated_versions = PromptVersion.deprecated
          expect(deprecated_versions).to include(deprecated)
          expect(deprecated_versions).not_to include(active)
        end
      end

      describe ".draft" do
        it "returns only draft versions" do
          active = PromptVersion.create!(valid_attributes.merge(status: "active"))
          draft = PromptVersion.create!(valid_attributes.merge(version_number: 2, status: "draft"))

          draft_versions = PromptVersion.draft
          expect(draft_versions).to include(draft)
          expect(draft_versions).not_to include(active)
        end
      end



      describe ".by_version" do
        it "orders by version_number descending" do
          v1 = PromptVersion.create!(valid_attributes.merge(version_number: 1))
          v3 = PromptVersion.create!(valid_attributes.merge(version_number: 3))
          v2 = PromptVersion.create!(valid_attributes.merge(version_number: 2))

          versions = prompt.prompt_versions.by_version.to_a
          expect(versions).to eq([ v3, v2, v1 ])
        end
      end
    end

    # Render Method Tests

    describe "#render" do
      let(:version) { PromptVersion.create!(valid_attributes) }

      it "substitutes variables in template" do
        rendered = version.render(name: "John", issue: "billing")
        expect(rendered).to eq("Hello John, how can I help with billing?")
      end

      it "handles missing optional variables gracefully" do
        rendered = version.render(name: "John")
        # Liquid renders missing variables as empty strings
        expect(rendered).to eq("Hello John, how can I help with ?")
      end

      it "raises error for missing required variables" do
        expect do
          version.render(issue: "billing") # missing required 'name'
        end.to raise_error(ArgumentError, /Missing required variables: name/)
      end

      it "works with symbol keys" do
        rendered = version.render(name: "John", issue: "billing")
        expect(rendered).to eq("Hello John, how can I help with billing?")
      end

      it "works with string keys" do
        rendered = version.render("name" => "John", "issue" => "billing")
        expect(rendered).to eq("Hello John, how can I help with billing?")
      end
    end

    # Activation Method Tests

    describe "#activate!" do
      it "sets status to active" do
        version = PromptVersion.create!(valid_attributes.merge(status: "draft"))
        version.activate!
        expect(version.reload.status).to eq("active")
      end

      it "deprecates other versions of same prompt" do
        v1 = PromptVersion.create!(valid_attributes.merge(version_number: 1, status: "active"))
        v2 = PromptVersion.create!(valid_attributes.merge(version_number: 2, status: "draft"))

        v2.activate!

        expect(v1.reload.status).to eq("deprecated")
        expect(v2.reload.status).to eq("active")
      end

      it "does not affect versions of other prompts" do
        other_prompt = Prompt.create!(name: "other_prompt")
        other_version = PromptVersion.create!(valid_attributes.merge(prompt: other_prompt, status: "active"))

        version = PromptVersion.create!(valid_attributes)
        version.activate!

        expect(other_version.reload.status).to eq("active")
      end
    end

    describe "#deprecate!" do
      it "sets status to deprecated" do
        version = PromptVersion.create!(valid_attributes.merge(status: "active"))
        version.deprecate!
        expect(version.reload.status).to eq("deprecated")
      end
    end

    # Status Check Methods

    describe "status check methods" do
      it "#active? returns true for active versions" do
        version = PromptVersion.create!(valid_attributes.merge(status: "active"))
        expect(version.active?).to be true
      end

      it "#deprecated? returns true for deprecated versions" do
        version = PromptVersion.create!(valid_attributes.merge(status: "deprecated"))
        expect(version.deprecated?).to be true
      end

      it "#draft? returns true for draft versions" do
        version = PromptVersion.create!(valid_attributes.merge(status: "draft"))
        expect(version.draft?).to be true
      end
    end

    # Display & Utility Methods

    describe "#name" do
      it "returns formatted name without status for active versions" do
        version = PromptVersion.create!(valid_attributes.merge(version_number: 1, status: "active"))
        expect(version.name).to eq("v1")
      end

      it "returns formatted name with status for non-active versions" do
        version = PromptVersion.create!(valid_attributes.merge(version_number: 2, status: "draft"))
        expect(version.name).to eq("v2 (draft)")
      end
    end

    describe "#display_name" do
      it "is an alias for #name" do
        version = PromptVersion.create!(valid_attributes.merge(version_number: 1, status: "active"))
        expect(version.display_name).to eq(version.name)
      end
    end

    describe "#has_responses?" do
      it "returns false when no responses exist" do
        version = PromptVersion.create!(valid_attributes)
        expect(version.has_responses?).to be false
      end

      it "returns true when responses exist" do
        version = PromptVersion.create!(valid_attributes)
        version.llm_responses.create!(
          rendered_prompt: "Test",
          response_text: "Response",
          model: "gpt-4",
          provider: "openai",
          status: "success"
        )
        expect(version.has_responses?).to be true
      end
    end

    describe "#to_yaml_export" do
      it "returns hash with all fields" do
        version = PromptVersion.create!(valid_attributes)
        export = version.to_yaml_export

        expect(export["name"]).to eq(prompt.name)
        expect(export["description"]).to eq(prompt.description)
        expect(export["category"]).to eq(prompt.category)
        expect(export["user_prompt"]).to eq(version.user_prompt)
        expect(export["system_prompt"]).to eq(version.system_prompt)
        expect(export["variables"]).to eq(version.variables_schema)
        expect(export["model_config"]).to eq(version.model_config)
      end
    end

    # Statistics Methods

    describe "statistics methods" do
      let(:version) { PromptVersion.create!(valid_attributes) }

      describe "#average_response_time_ms" do
        it "returns nil when no responses" do
          expect(version.average_response_time_ms).to be_nil
        end

        it "returns average response time" do
          version.llm_responses.create!(
            rendered_prompt: "Test 1",
            response_text: "Response 1",
            model: "gpt-4",
            provider: "openai",
            status: "success",
            response_time_ms: 100
          )

          version.llm_responses.create!(
            rendered_prompt: "Test 2",
            response_text: "Response 2",
            model: "gpt-4",
            provider: "openai",
            status: "success",
            response_time_ms: 200
          )

          expect(version.average_response_time_ms).to eq(150.0)
        end
      end

      describe "#total_cost_usd" do
        it "returns sum of costs" do
          version.llm_responses.create!(
            rendered_prompt: "Test 1",
            response_text: "Response 1",
            model: "gpt-4",
            provider: "openai",
            status: "success",
            cost_usd: 0.05
          )

          version.llm_responses.create!(
            rendered_prompt: "Test 2",
            response_text: "Response 2",
            model: "gpt-4",
            provider: "openai",
            status: "success",
            cost_usd: 0.03
          )

          expect(version.total_cost_usd).to eq(0.08)
        end
      end

      describe "#total_llm_calls" do
        it "returns count" do
          expect(version.total_llm_calls).to eq(0)

          version.llm_responses.create!(
            rendered_prompt: "Test",
            response_text: "Response",
            model: "gpt-4",
            provider: "openai",
            status: "success"
          )

          expect(version.total_llm_calls).to eq(1)
        end
      end
    end

    # Evaluator Config Methods

    describe "#has_monitoring_enabled?" do
      it "returns false when no enabled configs exist" do
        version = PromptVersion.create!(valid_attributes)
        expect(version.has_monitoring_enabled?).to be false
      end

      it "returns true when enabled configs exist" do
        version = PromptVersion.create!(valid_attributes)
        version.evaluator_configs.create!(
          evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
          enabled: true,
          config: { min_length: 10, max_length: 100 }
        )
        expect(version.has_monitoring_enabled?).to be true
      end
    end

    describe "#has_response_schema?" do
      it "returns false when no response_schema is defined" do
        version = PromptVersion.create!(valid_attributes)
        expect(version.has_response_schema?).to be false
      end

      it "returns true when response_schema is defined" do
        schema = { "type" => "object", "properties" => { "name" => { "type" => "string" } } }
        version = PromptVersion.create!(valid_attributes.merge(response_schema: schema))
        expect(version.has_response_schema?).to be true
      end
    end

    describe "#structured_output_enabled?" do
      let(:valid_schema) { { "type" => "object", "properties" => { "name" => { "type" => "string" } } } }

      it "returns false when no response_schema is defined" do
        version = PromptVersion.create!(valid_attributes)
        expect(version.structured_output_enabled?).to be false
      end

      it "returns false when model does not support structured output" do
        version = PromptVersion.create!(valid_attributes.merge(
                                          response_schema: valid_schema,
                                          model_config: { "provider" => "unknown", "model" => "some-model" }
                                        ))
        expect(version.structured_output_enabled?).to be false
      end

      it "returns true for OpenAI gpt-4o models with response_schema" do
        version = PromptVersion.create!(valid_attributes.merge(
                                          response_schema: valid_schema,
                                          model_config: { "provider" => "openai", "model" => "gpt-4o" }
                                        ))
        expect(version.structured_output_enabled?).to be true
      end

      it "returns true for OpenAI gpt-4o-mini models with response_schema" do
        version = PromptVersion.create!(valid_attributes.merge(
                                          response_schema: valid_schema,
                                          model_config: { "provider" => "openai", "model" => "gpt-4o-mini" }
                                        ))
        expect(version.structured_output_enabled?).to be true
      end

      it "returns true for Anthropic Claude 3 models with response_schema" do
        version = PromptVersion.create!(valid_attributes.merge(
                                          response_schema: valid_schema,
                                          model_config: { "provider" => "anthropic", "model" => "claude-3-5-sonnet" }
                                        ))
        expect(version.structured_output_enabled?).to be true
      end
    end

    describe "#response_schema_required_properties" do
      it "returns empty array when no response_schema is defined" do
        version = PromptVersion.create!(valid_attributes)
        expect(version.response_schema_required_properties).to eq([])
      end

      it "returns required properties from schema" do
        schema = {
          "type" => "object",
          "properties" => { "name" => { "type" => "string" }, "age" => { "type" => "integer" } },
          "required" => %w[name age]
        }
        version = PromptVersion.create!(valid_attributes.merge(response_schema: schema))
        expect(version.response_schema_required_properties).to eq(%w[name age])
      end
    end

    describe "#response_schema_properties" do
      it "returns empty hash when no response_schema is defined" do
        version = PromptVersion.create!(valid_attributes)
        expect(version.response_schema_properties).to eq({})
      end

      it "returns properties from schema" do
        schema = {
          "type" => "object",
          "properties" => { "name" => { "type" => "string" } }
        }
        version = PromptVersion.create!(valid_attributes.merge(response_schema: schema))
        expect(version.response_schema_properties).to eq({ "name" => { "type" => "string" } })
      end
    end

    # Archive functionality tests
    describe "archive functionality" do
      let(:version) { PromptVersion.create!(valid_attributes) }

      describe "#archive!" do
        it "sets archived_at timestamp" do
          expect {
            version.archive!
          }.to change { version.archived_at }.from(nil).to(be_present)
        end

        it "persists the archived_at timestamp" do
          version.archive!
          version.reload
          expect(version.archived_at).to be_present
        end
      end

      describe "#unarchive!" do
        before { version.archive! }

        it "clears archived_at timestamp" do
          expect {
            version.unarchive!
          }.to change { version.archived_at }.from(be_present).to(nil)
        end

        it "persists the change" do
          version.unarchive!
          version.reload
          expect(version.archived_at).to be_nil
        end
      end

      describe "#archived?" do
        it "returns false when not archived" do
          expect(version.archived?).to be false
        end

        it "returns true when archived" do
          version.archive!
          expect(version.archived?).to be true
        end
      end

      describe ".not_archived scope" do
        let!(:active_version) { PromptVersion.create!(valid_attributes) }
        let!(:archived_version) { PromptVersion.create!(valid_attributes.merge(version_number: 2)) }

        before { archived_version.archive! }

        it "returns only non-archived versions" do
          expect(PromptVersion.not_archived).to include(active_version)
          expect(PromptVersion.not_archived).not_to include(archived_version)
        end
      end

      describe ".archived scope" do
        let!(:active_version) { PromptVersion.create!(valid_attributes) }
        let!(:archived_version) { PromptVersion.create!(valid_attributes.merge(version_number: 2)) }

        before { archived_version.archive! }

        it "returns only archived versions" do
          expect(PromptVersion.archived).to include(archived_version)
          expect(PromptVersion.archived).not_to include(active_version)
        end
      end
    end
  end
end
