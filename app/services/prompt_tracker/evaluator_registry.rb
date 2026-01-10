# frozen_string_literal: true

module PromptTracker
  # Central registry for discovering and managing evaluators.
  #
  # The EvaluatorRegistry provides a single source of truth for all available
  # evaluators in the system. It allows:
  # - Discovering what evaluators are available
  # - Getting metadata about evaluators (name, description, config schema)
  # - Building evaluator instances
  # - Registering custom evaluators
  #
  # @example Getting all available evaluators
  #   EvaluatorRegistry.all
  #   # => {
  #   #   length: { name: "Length Validator", class: LengthEvaluator, ... },
  #   #   keyword: { name: "Keyword Checker", class: KeywordEvaluator, ... }
  #   # }
  #
  # @example Building an evaluator instance
  #   evaluator = EvaluatorRegistry.build(
  #     :length,
  #     llm_response.response_text,
  #     { llm_response: llm_response, min_length: 50 }
  #   )
  #   result = evaluator.evaluate
  #
  # @example Registering a custom evaluator
  #   EvaluatorRegistry.register(
  #     key: :sentiment_check,
  #     name: "Sentiment Analyzer",
  #     description: "Analyzes response sentiment",
  #     evaluator_class: MySentimentEvaluator,
  #     category: :content,
  #     config_schema: {
  #       positive_keywords: { type: :array, default: [] },
  #       negative_keywords: { type: :array, default: [] }
  #     }
  #   )
  #
  class EvaluatorRegistry
    class << self
      # Returns all registered evaluators
      #
      # @return [Hash] hash of evaluator_key => metadata
      def all
        registry
      end

      # Returns evaluators compatible with a specific testable
      # @deprecated Use for_test or for_mode instead
      #
      # @param testable [Object] the testable to filter by (e.g., PromptVersion, Assistant)
      # @return [Hash] hash of evaluator_key => metadata for compatible evaluators
      def for_testable(testable)
        all.select { |_key, meta| meta[:evaluator_class].compatible_with?(testable) }
      end

      # Returns evaluators compatible with a specific test (by test_mode and testable)
      #
      # V2 Architecture: Filters by:
      # 1. Test mode (single_turn -> single_response evaluators, conversational -> conversational)
      # 2. API compatibility (based on testable's api_type)
      #
      # @param test [Test] the test to filter evaluators for
      # @return [Hash] hash of evaluator_key => metadata for compatible evaluators
      # @example
      #   EvaluatorRegistry.for_test(single_turn_test)
      #   # => { length: {...}, keyword: {...}, llm_judge: {...} }
      #   EvaluatorRegistry.for_test(conversational_assistant_test)
      #   # => { conversation_judge: {...}, file_search: {...}, function_call: {...} }
      def for_test(test)
        test_mode = test.test_mode || "single_turn"
        testable = test.testable

        # Use V2 API-based filtering if testable supports api_type
        if testable.respond_to?(:api_type)
          for_test_v2(test)
        else
          # Fall back to legacy mode-based filtering
          for_mode(test_mode, testable: testable)
        end
      end

      # V2 Architecture: Returns evaluators for a specific test
      # Filters by test mode category AND API type compatibility
      #
      # @param test [Test] the test to filter evaluators for
      # @return [Hash] hash of evaluator_key => metadata for compatible evaluators
      def for_test_v2(test)
        category = test.single_turn? ? :single_response : :conversational
        api_type = test.testable.api_type

        all.select do |_key, meta|
          klass = meta[:evaluator_class]
          klass.category == category && klass.compatible_with_api?(api_type)
        end
      end

      # Returns evaluators by category
      #
      # @param category [Symbol] :single_response or :conversational
      # @return [Hash] hash of evaluator_key => metadata
      def by_category(category)
        all.select { |_key, meta| meta[:evaluator_class].category == category }
      end

      # Returns single_response evaluators
      #
      # @return [Hash] hash of evaluator_key => metadata
      def single_response_evaluators
        by_category(:single_response)
      end

      # Returns conversational evaluators
      #
      # @return [Hash] hash of evaluator_key => metadata
      def conversational_evaluators
        by_category(:conversational)
      end

      # Returns evaluators compatible with a specific API type
      #
      # @param api_type [Symbol] the API type to filter by
      # @return [Hash] hash of evaluator_key => metadata for compatible evaluators
      def for_api(api_type)
        all.select { |_key, meta| meta[:evaluator_class].compatible_with_api?(api_type) }
      end

      # Returns evaluators compatible with a specific mode and optional testable
      # @deprecated Use for_test_v2 with api_type-based filtering instead
      #
      # @param test_mode [String, Symbol] the test mode (:single_turn or :conversational)
      # @param testable [Object, nil] optional testable for additional filtering
      # @return [Hash] hash of evaluator_key => metadata for compatible evaluators
      def for_mode(test_mode, testable: nil)
        all.select do |_key, meta|
          klass = meta[:evaluator_class]

          if test_mode.to_s == "single_turn"
            # Only single-response evaluators
            klass < Evaluators::SingleResponse::BaseSingleResponseEvaluator
          elsif testable.is_a?(PromptTracker::Openai::Assistant)
            # All conversational evaluators (including Assistants-specific)
            klass < Evaluators::Conversational::BaseConversationalEvaluator
          elsif testable.present?
            # PromptVersion in conversational mode - exclude Assistants-specific
            klass < Evaluators::Conversational::BaseConversationalEvaluator &&
              !(klass < Evaluators::Conversational::BaseAssistantsApiEvaluator)
          else
            # No testable specified - show all conversational (conservative default)
            klass < Evaluators::Conversational::BaseConversationalEvaluator
          end
        end
      end

      # Gets metadata for a specific evaluator
      #
      # @param key [Symbol, String] the evaluator key
      # @return [Hash, nil] evaluator metadata or nil if not found
      def get(key)
        registry[key.to_sym]
      end

      # Checks if an evaluator is registered
      #
      # @param key [Symbol, String] the evaluator key
      # @return [Boolean] true if evaluator exists
      def exists?(key)
        registry.key?(key.to_sym)
      end

      # Returns the appropriate normalizer for an API type
      #
      # @param api_type [Symbol] the API type from ApiTypes
      # @return [Evaluators::Normalizers::BaseNormalizer] the normalizer instance
      # @raise [ArgumentError] if API type is unknown
      #
      # @example Get normalizer for Chat Completion
      #   normalizer = EvaluatorRegistry.normalizer_for(ApiTypes::OPENAI_CHAT_COMPLETION)
      #   normalized = normalizer.normalize_single_response(raw_response)
      def normalizer_for(api_type)
        case api_type
        when ApiTypes::OPENAI_CHAT_COMPLETION
          Evaluators::Normalizers::ChatCompletionNormalizer.new
        when ApiTypes::OPENAI_RESPONSE_API
          Evaluators::Normalizers::ResponseApiNormalizer.new
        when ApiTypes::OPENAI_ASSISTANTS_API
          Evaluators::Normalizers::AssistantsApiNormalizer.new
        when ApiTypes::ANTHROPIC_MESSAGES
          Evaluators::Normalizers::AnthropicNormalizer.new
        else
          raise ArgumentError, "Unknown API type: #{api_type}"
        end
      end

      # Builds an instance of an evaluator
      #
      # @param key [Symbol, String] the evaluator key
      # @param evaluated_data [String, Hash] the data to evaluate
      #   - For PromptVersion evaluators: String (response_text)
      #   - For Assistant evaluators: Hash (conversation_data)
      # @param config [Hash] configuration for the evaluator
      #   - Should include :llm_response or :test_run for context
      # @return [BaseEvaluator] an instance of the evaluator
      # @raise [ArgumentError] if evaluator not found
      #
      # @example Building a PromptVersion evaluator
      #   evaluator = EvaluatorRegistry.build(
      #     :length,
      #     llm_response.response_text,
      #     { llm_response: llm_response }
      #   )
      #
      # @example Building an Assistant evaluator
      #   evaluator = EvaluatorRegistry.build(
      #     :conversation_judge,
      #     test_run.conversation_data,
      #     { test_run: test_run }
      #   )
      def build(key, evaluated_data, config = {})
        metadata = get(key)
        raise ArgumentError, "Evaluator '#{key}' not found in registry" unless metadata

        evaluator_class = metadata[:evaluator_class]
        evaluator_class.new(evaluated_data, config)
      end

      # Registers a new evaluator
      #
      # @param key [Symbol] unique key for the evaluator
      # @param name [String] human-readable name
      # @param description [String] description of what it evaluates
      # @param evaluator_class [Class] the evaluator class
      # @param icon [String] Bootstrap icon name (without 'bi-' prefix)
      # @param default_config [Hash] default configuration values
      # @param form_template [String] path to the form partial for manual evaluation (optional)
      # @return [void]
      def register(key:, name:, description:, evaluator_class:, icon:, default_config: {}, form_template: nil)
        registry[key.to_sym] = {
          key: key.to_sym,
          name: name,
          description: description,
          evaluator_class: evaluator_class,
          icon: icon,
          default_config: default_config,
          form_template: form_template
        }
      end

      # Unregisters an evaluator (useful for testing)
      #
      # @param key [Symbol, String] the evaluator key
      # @return [void]
      def unregister(key)
        registry.delete(key.to_sym)
      end

      # Resets the registry (useful for testing)
      #
      # @return [void]
      def reset!
        @registry = nil
        initialize_registry
      end

      private

      # Returns the registry hash (initializes if needed)
      #
      # @return [Hash] the registry
      def registry
        @registry ||= initialize_registry
      end

      # Initializes the registry with auto-discovered evaluators
      #
      # @return [Hash] the initialized registry
      def initialize_registry
        @registry = {}

        # Auto-discover all evaluator classes
        auto_discover_evaluators

        @registry
      end

      # Auto-discovers evaluator classes by convention
      #
      # Scans app/services/prompt_tracker/evaluators/ for evaluator classes
      # and registers them automatically based on naming conventions.
      #
      # @return [void]
      def auto_discover_evaluators
        evaluators_path = File.join(File.dirname(__FILE__), "evaluators", "*.rb")

        Dir.glob(evaluators_path).each do |file|
          # Skip base evaluator classes (both old and new naming)
          next if file.end_with?("base_evaluator.rb")
          next if file.end_with?("base_prompt_version_evaluator.rb")
          next if file.end_with?("base_openai_assistant_evaluator.rb")
          next if file.end_with?("base_chat_completion_evaluator.rb")
          next if file.end_with?("base_conversational_evaluator.rb")
          next if file.end_with?("base_assistants_api_evaluator.rb")
          # Skip backup files
          next if file.end_with?(".bak")

          # Extract class name from filename
          filename = File.basename(file, ".rb")
          class_name = filename.camelize

          begin
            # Constantize the class (Rails autoloading will load the file)
            evaluator_class = "PromptTracker::Evaluators::#{class_name}".constantize

            # Register the evaluator
            register_evaluator_by_convention(evaluator_class)
          rescue NameError => e
            Rails.logger.warn "Failed to load evaluator class #{class_name}: #{e.message}"
          rescue LoadError => e
            Rails.logger.warn "Failed to load evaluator file #{file}: #{e.message}"
          end
        end
      end

      # Registers an evaluator using naming conventions
      #
      # Derives all metadata from the class name and structure:
      # - Key: class name without "Evaluator" suffix, underscored
      # - Name: class name without "Evaluator" suffix, titleized
      # - Form template: derived from key for human/llm_judge evaluators
      # - Icon, description, default_config: from evaluator class metadata
      #
      # @param evaluator_class [Class] the evaluator class to register
      # @return [void]
      def register_evaluator_by_convention(evaluator_class)
        # Derive key from class name
        # e.g., "KeywordEvaluator" -> "keyword"
        class_base_name = evaluator_class.name.demodulize
        key = class_base_name.underscore.gsub("_evaluator", "").to_sym

        # Derive human-readable name
        # e.g., "KeywordEvaluator" -> "Keyword"
        name = class_base_name.gsub("Evaluator", "").titleize

        # Get metadata from class (required)
        unless evaluator_class.respond_to?(:metadata)
          Rails.logger.warn "Evaluator #{evaluator_class.name} does not define .metadata class method"
          return
        end

        metadata = evaluator_class.metadata

        # Validate required metadata
        unless metadata[:icon]
          Rails.logger.warn "Evaluator #{evaluator_class.name} metadata missing required :icon"
          return
        end

        # Build form template path for human/llm_judge evaluators
        form_template = if [ "HumanEvaluator", "LlmJudgeEvaluator" ].include?(class_base_name)
          "prompt_tracker/evaluator_configs/forms/#{key}"
        else
          nil
        end

        # Register with metadata from class
        register(
          key: key,
          name: metadata[:name] || name,
          description: metadata[:description] || "Evaluates using #{name}",
          evaluator_class: evaluator_class,
          icon: metadata[:icon],
          default_config: metadata[:default_config] || {},
          form_template: form_template
        )
      end
    end
  end
end
