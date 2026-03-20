# frozen_string_literal: true

module PromptTracker
  module CloudProviders
    module Aws
      # Configuration for AWS Lambda runtime support
      # Defines supported languages and their runtime identifiers
      #
      # @see https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html
      class LambdaConfig
        # Supported languages and their AWS Lambda runtime identifiers
        # Format: { language_name => { label:, runtime:, deprecation_date: } }
        SUPPORTED_LANGUAGES = {
          "ruby3.4" => {
            label: "Ruby 3.4",
            runtime: "ruby3.4",
            deprecation_date: "2028-03-31"
          },
          "ruby3.3" => {
            label: "Ruby 3.3",
            runtime: "ruby3.3",
            deprecation_date: "2027-03-31"
          },
          "ruby3.2" => {
            label: "Ruby 3.2",
            runtime: "ruby3.2",
            deprecation_date: "2026-03-31"
          },
          "python3.13" => {
            label: "Python 3.13",
            runtime: "python3.13",
            deprecation_date: "2029-10-31"
          },
          "python3.12" => {
            label: "Python 3.12",
            runtime: "python3.12",
            deprecation_date: "2028-10-31"
          },
          "python3.11" => {
            label: "Python 3.11",
            runtime: "python3.11",
            deprecation_date: "2027-10-31"
          },
          "nodejs24.x" => {
            label: "Node.js 24",
            runtime: "nodejs24.x",
            deprecation_date: "2028-04-30"
          },
          "nodejs22.x" => {
            label: "Node.js 22",
            runtime: "nodejs22.x",
            deprecation_date: "2027-04-30"
          },
          "nodejs20.x" => {
            label: "Node.js 20",
            runtime: "nodejs20.x",
            deprecation_date: "2026-04-30"
          }
        }.freeze

        # Get all supported languages for display in forms
        # @return [Array<Hash>] Array of { value:, label:, runtime:, deprecated: }
        def self.available_languages
          SUPPORTED_LANGUAGES.map do |key, config|
            {
              value: key,
              label: config[:label],
              runtime: config[:runtime],
              deprecated: deprecated?(config[:deprecation_date])
            }
          end
        end

        # Get runtime identifier for a language
        # @param language [String] Language key (e.g., "ruby3.3")
        # @return [String, nil] Runtime identifier (e.g., "ruby3.3")
        def self.runtime_for(language)
          SUPPORTED_LANGUAGES.dig(language, :runtime)
        end

        # Check if a language is supported
        # @param language [String] Language key
        # @return [Boolean]
        def self.supported?(language)
          SUPPORTED_LANGUAGES.key?(language)
        end

        # Get default language
        # @return [String] Default language key
        def self.default_language
          "ruby3.3"
        end

        # Map AWS Lambda runtime to Monaco editor language identifier
        # @param runtime [String] AWS Lambda runtime identifier (e.g., "ruby3.3", "python3.12", "nodejs22.x")
        # @return [String] Monaco editor language identifier (e.g., "ruby", "python", "javascript")
        def self.monaco_language(runtime)
          case runtime
          when /^ruby/
            "ruby"
          when /^python/
            "python"
          when /^nodejs/
            "javascript"
          else
            "plaintext"
          end
        end

        private

        def self.deprecated?(deprecation_date)
          return false if deprecation_date.nil?

          Date.parse(deprecation_date) < Date.today
        rescue ArgumentError
          false
        end
      end
    end
  end
end
