# frozen_string_literal: true

require "liquid"

module PromptTracker
  # Service for rendering prompt templates with variable substitution using Liquid.
  #
  # @example Render with Liquid
  #   renderer = TemplateRenderer.new("Hello {{ name | upcase }}!")
  #   renderer.render(name: "john")
  #   # => "Hello JOHN!"
  #
  # @example Simple variable substitution
  #   renderer = TemplateRenderer.new("Hello {{name}}!")
  #   renderer.render(name: "John")
  #   # => "Hello John!"
  class TemplateRenderer
    attr_reader :template_string, :errors

    # Initialize a new template renderer
    #
    # @param template_string [String] the template to render
    def initialize(template_string)
      @template_string = template_string
      @errors = []
    end

    # Render the template with the given variables using Liquid
    #
    # @param variables [Hash] the variables to substitute
    # @param engine [Symbol] optional engine selection (:liquid or :mustache) - deprecated, always uses Liquid
    # @return [String] the rendered template
    # @raise [Liquid::SyntaxError] if Liquid template has syntax errors
    # @raise [ArgumentError] if unknown engine specified
    def render(variables = {}, engine: nil)
      # Validate engine parameter if provided
      if engine && ![ :liquid, :mustache ].include?(engine)
        raise ArgumentError, "Unknown template engine: #{engine}. Supported engines: :liquid, :mustache"
      end

      # Ensure we have a hash with indifferent access
      variables = if variables.is_a?(Hash)
        variables.with_indifferent_access
      else
        {}
      end

      render_with_liquid(variables)
    end

    # Check if template uses Liquid-specific syntax
    # Returns false for simple Mustache-style {{variable}} templates
    #
    # @return [Boolean] true if template uses Liquid features
    def liquid_template?
      # Check for Liquid-specific features:
      # - Filters: {{ variable | filter }}
      # - Tags: {% tag %}
      # - Object notation: {{ object.property }}
      template_string.match?(/\{\{[^}]*\|[^}]*\}\}/) ||  # Filters
        template_string.match?(/\{%.*%\}/) ||             # Tags
        template_string.match?(/\{\{\s*\w+\.\w+/)         # Object notation
    end

    # Check if the template is valid
    #
    # @return [Boolean] true if template is valid
    def valid?
      @errors = []

      # Try to parse as Liquid
      begin
        Liquid::Template.parse(template_string)
        true
      rescue Liquid::SyntaxError => e
        @errors << "Liquid syntax error: #{e.message}"
        false
      end
    end

    private

    # Render template using Liquid engine
    #
    # @param variables [Hash] the variables to substitute
    # @return [String] the rendered template
    def render_with_liquid(variables)
      template = Liquid::Template.parse(template_string)
      template.render(stringify_keys(variables))
    rescue Liquid::SyntaxError => e
      raise Liquid::SyntaxError, "Liquid template error: #{e.message}"
    end

    # Convert hash keys to strings for Liquid compatibility
    #
    # @param hash [Hash] the hash to convert
    # @return [Hash] hash with string keys
    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end
  end
end
