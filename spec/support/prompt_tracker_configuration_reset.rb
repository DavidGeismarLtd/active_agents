# frozen_string_literal: true

# Ensure PromptTracker.configuration global state is isolated between specs.
#
# Many specs mutate `PromptTracker.configuration.providers` and `contexts` in
# before blocks. Because the configuration object is a singleton, those
# mutations would otherwise leak across examples and even across spec files,
# which can make system specs order-dependent (they see whatever a previous
# spec left behind).
#
# This helper snapshots the configuration after the dummy app initializer has
# run, then restores it after each example. That keeps each example isolated
# while still using the real initializer defaults as the baseline.

PROMPT_TRACKER_CONFIG_SNAPSHOT = {} unless defined?(PROMPT_TRACKER_CONFIG_SNAPSHOT)

RSpec.configure do |config|
  config.before(:suite) do
    base_config = PromptTracker.configuration

    PROMPT_TRACKER_CONFIG_SNAPSHOT[:providers] = base_config.providers.deep_dup
    PROMPT_TRACKER_CONFIG_SNAPSHOT[:contexts] = base_config.contexts.deep_dup
    PROMPT_TRACKER_CONFIG_SNAPSHOT[:features] = base_config.features.deep_dup
    PROMPT_TRACKER_CONFIG_SNAPSHOT[:builtin_tools] = base_config.builtin_tools.deep_dup
    PROMPT_TRACKER_CONFIG_SNAPSHOT[:function_providers] = base_config.function_providers.deep_dup
    PROMPT_TRACKER_CONFIG_SNAPSHOT[:assistant_chatbot] = base_config.assistant_chatbot.deep_dup
    PROMPT_TRACKER_CONFIG_SNAPSHOT[:base_record_class] = base_config.base_record_class
    PROMPT_TRACKER_CONFIG_SNAPSHOT[:configuration_provider] = base_config.configuration_provider
    PROMPT_TRACKER_CONFIG_SNAPSHOT[:url_options_provider] = base_config.url_options_provider
    PROMPT_TRACKER_CONFIG_SNAPSHOT[:agent_base_url] = base_config.agent_base_url
    PROMPT_TRACKER_CONFIG_SNAPSHOT[:agent_callback_path] = base_config.agent_callback_path
    PROMPT_TRACKER_CONFIG_SNAPSHOT[:default_deployment_config] = base_config.default_deployment_config.deep_dup
  end

  config.around(:each) do |example|
    example.run
  ensure
    snapshot = PROMPT_TRACKER_CONFIG_SNAPSHOT
    config_obj = PromptTracker.configuration

    config_obj.providers = snapshot[:providers].deep_dup
    config_obj.contexts = snapshot[:contexts].deep_dup
    config_obj.features = snapshot[:features].deep_dup
    config_obj.builtin_tools = snapshot[:builtin_tools].deep_dup
    config_obj.function_providers = snapshot[:function_providers].deep_dup
    config_obj.assistant_chatbot = snapshot[:assistant_chatbot].deep_dup
    config_obj.base_record_class = snapshot[:base_record_class]
    config_obj.configuration_provider = snapshot[:configuration_provider]
    config_obj.url_options_provider = snapshot[:url_options_provider]
    config_obj.agent_base_url = snapshot[:agent_base_url]
    config_obj.agent_callback_path = snapshot[:agent_callback_path]
    config_obj.default_deployment_config = snapshot[:default_deployment_config].deep_dup

      PromptTracker::EvaluatorRegistry.reset!
  end
end
