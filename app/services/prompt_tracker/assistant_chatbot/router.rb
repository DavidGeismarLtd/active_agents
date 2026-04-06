# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
      # Routes incoming assistant requests to specialized assistants
      # based on the current page context and user message.
      #
      # Routing is performed with a lightweight LLM classification
      # call. This keeps the AssistantChatbotService free from
      # brittle string matching while making it easy to extend to
      # more assistants (dataset wizard, deployment wizard, etc.).
      class Router
        # Determine which specialized assistant (wizard) should handle
        # the current message.
        #
        # @param message [String] raw user message
        # @param context [Hash] page / UI context (e.g., :page_type, :agent_version_id)
        # @return [Symbol] one of:
        #   :docs_wizard, :test_runner_wizard, :test_creator_wizard, :dataset_wizard,
        #   :agent_creation_wizard, :deployment_wizard, or :no_match
        def self.assistant_for(message:, context: {})
          new(message: message, context: context).assistant
        end

        def initialize(message:, context: {})
          @message = message.to_s
          @context = context || {}
        end

        def assistant
            # Only call the LLM router when there is an actual user message.
            # This avoids unnecessary LLM calls for empty payloads.
            return :no_match if message.strip.empty?

          Rails.logger.debug(
            "[AssistantChatbot::Router] routing message=#{message.inspect} " \
            "page_type=#{context[:page_type].inspect}"
          )

          classify_with_llm
        end

      private

      attr_reader :message, :context

        def classify_with_llm
            system_prompt = <<~PROMPT.strip
	          You are a router for the PromptTracker assistant.

	          Read the current page context, the recent conversation (if any),
	          and the user's latest message. Decide which specialized assistant
	          (if any) should handle the request.

	          The context may include an "active_assistant" field indicating
	          which wizard was previously chosen. If the recent conversation
	          shows that wizard is mid-flow (for example, the assistant asked a
	          question and the user is answering it), you should usually return
	          that same wizard again unless the new message clearly asks to
	          switch to a different workflow (like running tests or deploying an
	          agent).

		          Return exactly ONE word from this list:
		          - "docs_wizard"
		          - "no_match"
	          - "test_runner_wizard"
	          - "test_creator_wizard"
	          - "dataset_wizard"
	          - "agent_creation_wizard"
	          - "deployment_wizard"

	          Use these guidelines:
		          - Use "docs_wizard" when the user is asking a general "how do I..." question
		            about PromptTracker (tracking calls, playground, testing, evaluators, UI usage)
		            and they are NOT asking to execute a workflow right now.
		          - Use "no_match" when the user message is unrelated to PromptTracker or you are
		            not confident which assistant applies.
	          - Use "test_runner_wizard" when the user clearly wants to run
	            or execute existing tests for an agent or agent version
	            (e.g. "run all tests", "execute the tests", "run regression
	            tests"). This is most relevant when tests already exist.
	          - Use "test_creator_wizard" when the user wants to create,
	            write, or generate new tests for an agent or agent version
	            (e.g. "write tests for this agent", "generate tests",
	            "create tests", "add tests").
	          - Use "dataset_wizard" when the user wants to create or set
	            up a dataset for an agent version (e.g. "create a dataset",
	            "generate a dataset for this version").
	          - Use "agent_creation_wizard" when the user wants to create
	            or configure a brand new agent (e.g. "create a new agent",
	            "design an assistant", "configure an agent"). This wizard
	            helps choose the agent name, description, and model, but does
	            NOT deploy or start running the agent.
	          - Use "deployment_wizard" when the user wants to deploy an
	            existing agent or agent version as a live, running agent
	            (e.g. "deploy this agent", "make this live", "create an API
	            endpoint", "turn this agent on in production"). This wizard
	            configures runtime/deployment options only and does NOT design
	            the agent from scratch.
	          - When the message mixes creation and deployment (e.g. "create
	            a new agent and deploy it"), prefer "agent_creation_wizard"
	            so that the agent is designed first; deployment can happen in
	            a separate step.
		          - Use "no_match" for all other cases or when you are unsure.

	          Do not add any explanation.
          PROMPT

          history_section = if context[:conversation_summary].present?
            "Recent conversation:\n#{context[:conversation_summary]}\n\n"
          else
            ""
          end

          routing_prompt = <<~PROMPT.strip
	          Page type: #{context[:page_type] || "none"}
	          Prompt version id: #{context[:agent_version_id] || "none"}
	          Active assistant: #{context[:active_assistant] || "none"}

	          #{history_section}Latest user message:
	          #{message}
          PROMPT

          model_config = PromptTracker.configuration.assistant_chatbot_model
          provider = model_config[:provider]
          api = model_config[:api]
          model = router_model(model_config)
          temperature = 0

          Rails.logger.debug("[AssistantChatbot::Router] system_prompt=#{system_prompt[0..200]}...")
          Rails.logger.debug("[AssistantChatbot::Router] routing_prompt=#{routing_prompt[0..200]}...")

          normalized = LlmClientService.call(
            provider: provider,
            api: api,
            model: model,
            prompt: routing_prompt,
            temperature: temperature,
            response_schema: nil,
            system_prompt: system_prompt,
            tools: [],
            tool_config: {}
          )

          label = normalized.text.to_s.strip.downcase

          Rails.logger.debug("[AssistantChatbot::Router] normalized.text=#{normalized.text.inspect} label=#{label.inspect}")

            assistant = case label
            when "docs_wizard"
              :docs_wizard
            when "no_match"
              :no_match
            when "test_runner_wizard"
          :test_runner_wizard
            when "test_creator_wizard"
          :test_creator_wizard
            when "dataset_wizard"
          :dataset_wizard
            when "agent_creation_wizard"
            :agent_creation_wizard
            when "deployment_wizard"
          :deployment_wizard
            else
              :no_match
            end

          Rails.logger.info("[AssistantChatbot::Router] routing decision label=#{label.inspect} assistant=#{assistant.inspect}")
          assistant
      end

        def router_model(model_config)
          router_config = PromptTracker.configuration.assistant_chatbot[:router] || {}
          router_config[:model] || model_config[:model] || "gpt-4o-mini"
        end
      end
  end
end
