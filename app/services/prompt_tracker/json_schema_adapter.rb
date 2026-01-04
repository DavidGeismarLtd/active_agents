# frozen_string_literal: true

module PromptTracker
  # Adapter for converting JSON Schema (Hash) to RubyLLM::Schema classes.
  #
  # This enables using JSON Schema definitions stored in PromptVersion.response_schema
  # with RubyLLM's structured output feature.
  #
  # @example Convert a JSON Schema to RubyLLM::Schema
  #   json_schema = {
  #     "type" => "object",
  #     "properties" => {
  #       "sentiment" => { "type" => "string", "enum" => ["positive", "negative", "neutral"] },
  #       "confidence" => { "type" => "number" }
  #     },
  #     "required" => ["sentiment", "confidence"]
  #   }
  #
  #   schema_class = JsonSchemaAdapter.to_ruby_llm_schema(json_schema)
  #   chat = RubyLLM.chat(model: "gpt-4o").with_schema(schema_class)
  #
  class JsonSchemaAdapter
    # Convert a JSON Schema hash to a RubyLLM::Schema subclass
    #
    # @param json_schema [Hash] JSON Schema definition
    # @return [Class] a RubyLLM::Schema subclass
    # @raise [ArgumentError] if json_schema is invalid
    def self.to_ruby_llm_schema(json_schema)
      new(json_schema).build_schema_class
    end

    attr_reader :json_schema

    def initialize(json_schema)
      @json_schema = json_schema
      validate_schema!
    end

    # Build a dynamic RubyLLM::Schema subclass from the JSON Schema
    #
    # @return [Class] a RubyLLM::Schema subclass
    def build_schema_class
      properties = json_schema["properties"] || {}
      adapter = self

      Class.new(RubyLLM::Schema) do
        properties.each do |name, prop_schema|
          adapter.add_field_to_schema(self, name, prop_schema)
        end
      end
    end

    # Add a field to a RubyLLM::Schema class based on JSON Schema property
    #
    # @param schema_class [Class] the RubyLLM::Schema class being built
    # @param name [String] the field name
    # @param prop_schema [Hash] the JSON Schema property definition
    def add_field_to_schema(schema_class, name, prop_schema)
      field_name = name.to_sym
      description = prop_schema["description"]
      prop_type = prop_schema["type"]

      case prop_type
      when "string"
        schema_class.string field_name, description: description
      when "number", "integer"
        schema_class.number field_name, description: description
      when "boolean"
        schema_class.boolean field_name, description: description
      when "array"
        add_array_field(schema_class, field_name, prop_schema, description)
      when "object"
        add_object_field(schema_class, field_name, prop_schema, description)
      else
        # Default to string for unknown types
        schema_class.string field_name, description: description
      end
    end

    # Add an array field to the schema
    def add_array_field(schema_class, field_name, prop_schema, description)
      items_schema = prop_schema["items"] || {}
      items_type = items_schema["type"] || "string"
      items_properties = items_schema["properties"] || {}

      schema_class.array field_name, description: description do
        case items_type
        when "string"
          string
        when "number", "integer"
          number
        when "boolean"
          boolean
        when "object"
          object do
            items_properties.each do |nested_name, nested_schema|
              JsonSchemaAdapter.add_simple_field(self, nested_name.to_sym, nested_schema)
            end
          end
        else
          string
        end
      end
    end

    # Add an object field to the schema
    def add_object_field(schema_class, field_name, prop_schema, description)
      nested_properties = prop_schema["properties"] || {}

      schema_class.object field_name, description: description do
        nested_properties.each do |nested_name, nested_schema|
          JsonSchemaAdapter.add_simple_field(self, nested_name.to_sym, nested_schema)
        end
      end
    end

    # Add a simple (non-nested) field - used inside blocks
    # This is a class method so it can be called from within DSL blocks
    def self.add_simple_field(context, field_name, prop_schema)
      nested_type = prop_schema["type"] || "string"
      nested_desc = prop_schema["description"]

      case nested_type
      when "string"
        context.string field_name, description: nested_desc
      when "number", "integer"
        context.number field_name, description: nested_desc
      when "boolean"
        context.boolean field_name, description: nested_desc
      else
        context.string field_name, description: nested_desc
      end
    end

    private

    def validate_schema!
      raise ArgumentError, "json_schema must be a Hash" unless json_schema.is_a?(Hash)
      raise ArgumentError, "json_schema must have a 'type' property" unless json_schema["type"].present?

      if json_schema["type"] == "object" && json_schema["properties"].blank?
        raise ArgumentError, "json_schema must have 'properties' when type is 'object'"
      end
    end
  end
end
