# frozen_string_literal: true

#
# Bootstrap loaded by docker/agent-runtime-entrypoint.rb before any services
# from app/services are required. Provides the minimal environment those
# services expect — ActiveSupport core extensions, a Rails.logger stub, a
# PromptTracker.configuration stub, and a configured RubyLLM client.
#
# This script runs OUTSIDE of Rails. It must not depend on ActiveRecord,
# the Rails initializers, or anything else that requires an application boot.

require "logger"
require "active_support/all"

# Minimal Rails.logger so services that call Rails.logger.info don't crash.
unless defined?(Rails)
  module Rails
    @logger = Logger.new($stdout).tap do |l|
      l.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}] #{severity} -- #{msg}\n"
      end
    end

    def self.logger
      @logger
    end
  end
end

# Minimal PromptTracker.configuration stub. Shared LLM clients call:
# - .dynamic_configuration? (always false in the container — keys come from ENV)
# - .api_key_for(provider) (LlmClients::OpenaiResponseService for Responses API)
module PromptTracker
  class RuntimeStubConfiguration
    PROVIDER_ENV_KEYS = {
      openai: "OPENAI_API_KEY",
      anthropic: "ANTHROPIC_API_KEY",
      google: "GEMINI_API_KEY",
      gemini: "GEMINI_API_KEY",
      deepseek: "DEEPSEEK_API_KEY",
      mistral: "MISTRAL_API_KEY",
      perplexity: "PERPLEXITY_API_KEY",
      openrouter: "OPENROUTER_API_KEY",
      xai: "XAI_API_KEY"
    }.freeze

    def dynamic_configuration?
      false
    end

    def api_key_for(provider)
      ENV[PROVIDER_ENV_KEYS[provider.to_sym].to_s]
    end
  end

  class << self
    def configuration
      @configuration ||= RuntimeStubConfiguration.new
    end
  end
end

# Configure RubyLLM with whatever provider key was passed into the container.
# ContainerOrchestrator only forwards the key for the agent's active provider
# (see app/services/prompt_tracker/container_orchestrator.rb#scoped_api_keys).
require "ruby_llm"

RubyLLM.configure do |c|
  c.openai_api_key     = ENV["OPENAI_API_KEY"]     if ENV["OPENAI_API_KEY"]
  c.anthropic_api_key  = ENV["ANTHROPIC_API_KEY"]  if ENV["ANTHROPIC_API_KEY"]
  c.gemini_api_key     = ENV["GEMINI_API_KEY"]     if ENV["GEMINI_API_KEY"]
  c.deepseek_api_key   = ENV["DEEPSEEK_API_KEY"]   if ENV["DEEPSEEK_API_KEY"]
  c.mistral_api_key    = ENV["MISTRAL_API_KEY"]    if ENV["MISTRAL_API_KEY"]
  c.perplexity_api_key = ENV["PERPLEXITY_API_KEY"] if ENV["PERPLEXITY_API_KEY"]
  c.openrouter_api_key = ENV["OPENROUTER_API_KEY"] if ENV["OPENROUTER_API_KEY"]
  c.xai_api_key        = ENV["XAI_API_KEY"]        if ENV["XAI_API_KEY"]
end

# Load the shared service classes from app/services. We don't have Zeitwerk,
# so explicit requires in dependency order.
services_root = "/app/app/services"
$LOAD_PATH.unshift(services_root) unless $LOAD_PATH.include?(services_root)

require "prompt_tracker/normalized_llm_response"
require "prompt_tracker/llm_response_normalizers/base"
require "prompt_tracker/llm_response_normalizers/ruby_llm"
require "prompt_tracker/llm_response_normalizers/openai/responses"
require "prompt_tracker/ruby_llm/dynamic_tool_builder"
require "prompt_tracker/openai/responses/tool_formatter"
require "prompt_tracker/openai/responses/request_builder"
require "prompt_tracker/llm_clients/ruby_llm_service"
require "prompt_tracker/llm_clients/openai_response_service"
