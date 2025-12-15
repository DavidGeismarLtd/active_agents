# frozen_string_literal: true

require "rails_helper"
require "tempfile"

module PromptTracker
  RSpec.describe PromptFile do
    let(:valid_yaml) do
      <<~YAML
        name: test_prompt
        description: A test prompt
        user_prompt: |
          Hello {{name}}!
          How are you doing with {{topic}}?
        variables:
          - name: name
            type: string
            required: true
          - name: topic
            type: string
            required: false
        model_config:
          temperature: 0.7
          max_tokens: 150
        notes: This is a test prompt
      YAML
    end

    let(:temp_file) do
      file = Tempfile.new([ "test_prompt", ".yml" ])
      file.write(valid_yaml)
      file.close
      file
    end

    after do
      temp_file.unlink if temp_file
    end

    # Initialization Tests

    describe "#initialize" do
      it "initializes with path" do
        file = PromptFile.new(temp_file.path)
        expect(file.path).to eq(temp_file.path)
      end
    end

    # Validation Tests

    describe "#valid?" do
      it "is valid with valid YAML" do
        file = PromptFile.new(temp_file.path)
        expect(file).to be_valid
        expect(file.errors).to be_empty
      end

      it "is invalid if file does not exist" do
        file = PromptFile.new("/nonexistent/file.yml")
        expect(file).not_to be_valid
        expect(file.errors.first).to include("File does not exist")
      end

      it "is invalid with invalid YAML syntax" do
        temp = Tempfile.new([ "invalid", ".yml" ])
        temp.write("invalid: yaml: syntax:")
        temp.close

        file = PromptFile.new(temp.path)
        expect(file).not_to be_valid
        expect(file.errors).to include(a_string_including("Invalid YAML syntax"))

        temp.unlink
      end

      it "is invalid if YAML is not a hash" do
        temp = Tempfile.new([ "array", ".yml" ])
        temp.write("- item1\n- item2")
        temp.close

        file = PromptFile.new(temp.path)
        expect(file).not_to be_valid
        expect(file.errors.first).to include("must contain a hash")

        temp.unlink
      end

      it "requires name field" do
        yaml = valid_yaml.gsub("name: test_prompt", "")
        temp = create_temp_file(yaml)

        file = PromptFile.new(temp.path)
        expect(file).not_to be_valid
        expect(file.errors).to include(a_string_including("Missing required field: name"))

        temp.unlink
      end

      it "requires user_prompt field" do
        yaml = valid_yaml.gsub(/user_prompt:.*How are you doing with.*?\n/m, "")
        temp = create_temp_file(yaml)

        file = PromptFile.new(temp.path)
        expect(file).not_to be_valid
        expect(file.errors).to include(a_string_including("Missing required field: user_prompt"))

        temp.unlink
      end

      it "validates name format" do
        yaml = valid_yaml.gsub("name: test_prompt", "name: Invalid Name")
        temp = create_temp_file(yaml)

        file = PromptFile.new(temp.path)
        expect(file).not_to be_valid
        expect(file.errors).to include(a_string_including("lowercase letters, numbers, and underscores"))

        temp.unlink
      end

      it "validates variables is an array" do
        yaml = valid_yaml.gsub(/variables:.*?model_config:/m, "variables: not_an_array\nmodel_config:")
        temp = create_temp_file(yaml)

        file = PromptFile.new(temp.path)
        expect(file).not_to be_valid
        expect(file.errors).to include(a_string_including("variables' must be an array"))

        temp.unlink
      end

      it "validates model_config is a hash" do
        yaml = valid_yaml.gsub("model_config:\n  temperature: 0.7\n  max_tokens: 150", "model_config: not_a_hash")
        temp = create_temp_file(yaml)

        file = PromptFile.new(temp.path)
        expect(file).not_to be_valid
        expect(file.errors).to include(a_string_including("model_config' must be a hash"))

        temp.unlink
      end

      it "validates user_prompt variables match schema" do
        yaml = <<~YAML
          name: test_prompt
          user_prompt: "Hello {{name}} and {{unknown_var}}"
          variables:
            - name: name
              type: string
        YAML
        temp = create_temp_file(yaml)

        file = PromptFile.new(temp.path)
        expect(file).not_to be_valid
        expect(file.errors).to include(a_string_matching(/not defined in schema.*unknown_var/))

        temp.unlink
      end
    end

    # Accessor Tests

    describe "accessors" do
      let(:file) { PromptFile.new(temp_file.path) }

      it "returns name" do
        expect(file.name).to eq("test_prompt")
      end

      it "returns user_prompt" do
        expect(file.user_prompt).to include("Hello {{name}}")
      end

      it "returns description" do
        expect(file.description).to eq("A test prompt")
      end

      it "returns variables" do
        expect(file.variables.length).to eq(2)
        expect(file.variables.first["name"]).to eq("name")
      end

      it "returns model_config" do
        expect(file.model_config["temperature"]).to eq(0.7)
        expect(file.model_config["max_tokens"]).to eq(150)
      end

      it "returns notes" do
        expect(file.notes).to eq("This is a test prompt")
      end
    end

    # File Info Tests

    describe "file information" do
      it "#exists? returns true for existing file" do
        file = PromptFile.new(temp_file.path)
        expect(file.exists?).to be true
      end

      it "#exists? returns false for non-existing file" do
        file = PromptFile.new("/nonexistent/file.yml")
        expect(file.exists?).to be false
      end

      it "#last_modified returns file mtime" do
        file = PromptFile.new(temp_file.path)
        expect(file.last_modified).to be_a(Time)
      end

      it "#last_modified returns nil for non-existing file" do
        file = PromptFile.new("/nonexistent/file.yml")
        expect(file.last_modified).to be_nil
      end
    end

    # Conversion Tests

    describe "#to_h" do
      it "returns hash with prompt and version data" do
        file = PromptFile.new(temp_file.path)
        hash = file.to_h

        expect(hash[:prompt][:name]).to eq("test_prompt")
        expect(hash[:prompt][:description]).to eq("A test prompt")

        expect(hash[:version][:user_prompt]).to include("Hello {{name}}")
        expect(hash[:version][:variables_schema].length).to eq(2)
        expect(hash[:version][:model_config]["temperature"]).to eq(0.7)
        expect(hash[:version][:notes]).to eq("This is a test prompt")
        expect(hash[:version][:source]).to eq("file")
      end
    end

    describe "#summary" do
      it "returns readable summary" do
        # Mock the configuration
        PromptTracker.configure do |config|
          config.prompts_path = File.dirname(temp_file.path)
        end

        file = PromptFile.new(temp_file.path)
        summary = file.summary

        expect(summary).to include("test_prompt")
        expect(summary).to include(File.basename(temp_file.path))
      end
    end

    def create_temp_file(content)
      temp = Tempfile.new([ "test", ".yml" ])
      temp.write(content)
      temp.close
      temp
    end
  end
end
