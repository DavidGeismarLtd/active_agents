# frozen_string_literal: true

module PromptTracker
  # Service for coordinating A/B test variant selection.
  #
  # This service determines which prompt version to use when an A/B test is running.
  # It handles:
  # - Checking if a prompt has an active A/B test
  # - Selecting a variant based on traffic split
  # - Returning the appropriate version
  #
  # @example Basic usage
  #   selection = AbTestCoordinator.select_version_for_prompt("customer_greeting")
  #   # => {
  #   #   version: <PromptVersion>,
  #   #   ab_test: <AbTest> or nil,
  #   #   variant: "A" or "B" or nil
  #   # }
  #
  # @example When no A/B test is running
  #   selection = AbTestCoordinator.select_version_for_prompt("greeting")
  #   selection[:version]  # => active version
  #   selection[:ab_test]  # => nil
  #   selection[:variant]  # => nil
  #
  # @example When A/B test is running
  #   selection = AbTestCoordinator.select_version_for_prompt("greeting")
  #   selection[:version]  # => version for selected variant
  #   selection[:ab_test]  # => <AbTest>
  #   selection[:variant]  # => "A" or "B"
  #
  class AbTestCoordinator
    # Selects the appropriate version for a prompt.
    #
    # If an A/B test is running for the prompt, selects a variant based on
    # traffic split. Otherwise, returns the active version.
    #
    # @param prompt_name [String] the name of the prompt
    # @return [Hash] selection hash with :version, :ab_test, :variant keys
    # @return [nil] if prompt not found
    #
    # @example
    #   selection = AbTestCoordinator.select_version_for_prompt("greeting")
    #   version = selection[:version]
    #   ab_test = selection[:ab_test]
    #   variant = selection[:variant]
    #
    def self.select_version_for_prompt(prompt_name)
      prompt = Prompt.find_by(name: prompt_name)
      return nil unless prompt

      # Check for running A/B test
      ab_test = prompt.ab_tests.running.first

      # No A/B test - return active version
      unless ab_test
        return {
          version: prompt.active_version,
          ab_test: nil,
          variant: nil
        }
      end

      # A/B test is running - select variant
      variant_name = ab_test.select_variant
      version = ab_test.version_for_variant(variant_name)

      {
        version: version,
        ab_test: ab_test,
        variant: variant_name
      }
    end

    # Selects a version for a specific prompt instance.
    #
    # Similar to select_version_for_prompt but takes a Prompt object instead of name.
    #
    # @param prompt [Prompt] the prompt instance
    # @return [Hash] selection hash with :version, :ab_test, :variant keys
    #
    # @example
    #   prompt = Prompt.find_by(name: "greeting")
    #   selection = AbTestCoordinator.select_version_for(prompt)
    #
    def self.select_version_for(prompt)
      return nil unless prompt

      # Check for running A/B test
      ab_test = prompt.ab_tests.running.first

      # No A/B test - return active version
      unless ab_test
        return {
          version: prompt.active_version,
          ab_test: nil,
          variant: nil
        }
      end

      # A/B test is running - select variant
      variant_name = ab_test.select_variant
      version = ab_test.version_for_variant(variant_name)

      {
        version: version,
        ab_test: ab_test,
        variant: variant_name
      }
    end

    # Checks if a prompt has a running A/B test.
    #
    # @param prompt_name [String] the name of the prompt
    # @return [Boolean] true if A/B test is running
    #
    # @example
    #   AbTestCoordinator.ab_test_running?("greeting")  # => true or false
    #
    def self.ab_test_running?(prompt_name)
      prompt = Prompt.find_by(name: prompt_name)
      return false unless prompt

      prompt.ab_tests.running.exists?
    end

    # Gets the running A/B test for a prompt.
    #
    # @param prompt_name [String] the name of the prompt
    # @return [AbTest, nil] the running test or nil
    #
    # @example
    #   ab_test = AbTestCoordinator.get_running_test("greeting")
    #
    def self.get_running_test(prompt_name)
      prompt = Prompt.find_by(name: prompt_name)
      return nil unless prompt

      prompt.ab_tests.running.first
    end

    # Validates that a variant selection is valid for an A/B test.
    #
    # @param ab_test [AbTest] the A/B test
    # @param variant_name [String] the variant name to validate
    # @return [Boolean] true if variant is valid
    #
    # @example
    #   AbTestCoordinator.valid_variant?(ab_test, "A")  # => true
    #   AbTestCoordinator.valid_variant?(ab_test, "Z")  # => false
    #
    def self.valid_variant?(ab_test, variant_name)
      return false unless ab_test
      return false unless variant_name

      ab_test.variant_names.include?(variant_name)
    end
  end
end
