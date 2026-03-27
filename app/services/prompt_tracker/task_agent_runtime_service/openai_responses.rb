# frozen_string_literal: true

module PromptTracker
  class TaskAgentRuntimeService
    # OpenAI Responses API implementation for TaskAgentRuntimeService.
    #
    # The Responses API requires manual function call handling because it doesn't
    # support the function_executor pattern. Instead, we:
    # 1. Call the API
    # 2. Check for function calls in the response
    # 3. Execute functions
    # 4. Call the API again with results
    # 5. Repeat until no more function calls
    #
    # This subclass overrides only the `call_llm` method to handle the Responses API
    # function call loop, while inheriting all other task agent logic from the base class.
    #
    class OpenaiResponses < TaskAgentRuntimeService
      # Call OpenAI Responses API with manual function call handling
      #
      # @param messages [Array<Hash>] conversation messages
      # @param phase [Symbol] :planning or :execution
      # @return [Hash] normalized LLM response
      def call_llm(messages, phase: :execution)
        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🚀 Starting call_llm (phase: #{phase})"

        model_config = task_agent.prompt_version.model_config
        system_prompt = task_agent.prompt_version.system_prompt

        # Enhance system prompt with planning instructions if enabled
        if @planning_enabled
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🎯 Enhancing system prompt with planning instructions (phase: #{phase})"
          system_prompt = enhance_system_prompt_with_planning(system_prompt, phase: phase)
        end

        # Build tools array from function definitions + planning functions
        # IMPORTANT: respect the phase so that planning phase (iteration 0)
        # only exposes the planning tools (typically just create_plan).
        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🔧 Building tools array (phase: #{phase})..."
        tools_array = build_tools_array(phase: phase)

        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 📞 Calling Responses API with #{tools_array.length} function(s)"
        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 📝 User message: #{messages.last[:content][0..200]}..."

        # Extract user prompt from messages
        user_prompt = messages.last[:content]

        # Convert tools array to Responses API format
        tools = tools_array.present? ? [ :functions ] : []
        tool_config = { "functions" => tools_array }

        # Make initial API call
        # Note: Some models (like gpt-5-pro) don't support temperature parameter
        # GPT-5 models don't support temperature, so we pass nil to avoid sending it
        temperature = model_config["model"]&.start_with?("gpt-5") ? nil : model_config["temperature"]

        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🌡️  Temperature: #{temperature.inspect} (model: #{model_config['model']})"
        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] ⏳ Making initial API call (this may take a while for GPT-5)..."

        response = LlmClients::OpenaiResponseService.call(
          model: model_config["model"],
          input: user_prompt,
          instructions: system_prompt,
          tools: tools,
          tool_config: tool_config,
          temperature: temperature
        )

        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] ✅ Initial API call completed"
        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 📊 Response has #{response[:tool_calls]&.length || 0} tool calls"

        # Track the initial LLM response to capture the initial intent (tool calls)
        # This creates visibility into what the LLM decided to do BEFORE functions execute
        if response[:tool_calls].present?
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 📝 Tracking initial LLM response with tool calls"
          track_llm_response(response, rendered_prompt: user_prompt)
        end

        # Handle function call loop
        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🔄 Starting function call loop..."
        response = handle_function_call_loop(response, model_config, initial_prompt: user_prompt, phase: phase)

        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] ✅ call_llm completed successfully"
        response
      end

      private

      # Handle the function call loop for Responses API
      #
      # @param initial_response [NormalizedLlmResponse] the initial API response
      # @param model_config [Hash] model configuration
      # @param initial_prompt [String] the initial user prompt (for tracking)
      # @param phase [Symbol] :planning or :execution
      # @return [NormalizedLlmResponse] final response after all function calls
      def handle_function_call_loop(initial_response, model_config, initial_prompt: nil, phase: :execution)
        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🔄 Entering function call loop handler"

        response = initial_response
        iteration = 0
        max_iterations = 10

        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🔍 Checking for tool calls in initial response..."
        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 📋 Tool calls present: #{response[:tool_calls].present?}"

        while response[:tool_calls].present? && iteration < max_iterations
          iteration += 1
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🔁 Function call iteration #{iteration}/#{max_iterations}"

          tool_calls = response[:tool_calls]
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 📞 Received #{tool_calls.length} function call(s):"
          tool_calls.each_with_index do |tc, i|
            @logger.info "[TaskAgentRuntimeService::OpenaiResponses]   #{i+1}. #{tc[:function_name]} (id: #{tc[:id]})"
          end

          # Execute all function calls and build input items
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] ⚙️  Executing function calls..."
          input_items = execute_function_calls_and_build_input(tool_calls)
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] ✅ Built #{input_items.length} input items for continuation"

          # Get response_id from api_metadata
          response_id = response.dig(:api_metadata, :response_id)
          unless response_id
            @logger.error "[TaskAgentRuntimeService::OpenaiResponses] ❌ No response_id found in api_metadata"
            @logger.error "[TaskAgentRuntimeService::OpenaiResponses] 📊 Response keys: #{response.keys.inspect}"
            break
          end

          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🔗 Using response_id: #{response_id}"
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] ⏳ Calling API with function results (iteration #{iteration})..."

          # Call API with function results
          response = LlmClients::OpenaiResponseService.call_with_context(
            model: model_config["model"],
            input: input_items,
            previous_response_id: response_id,
            tools: [ :functions ],
            # Use the same phase-aware tool selection as the initial call
            tool_config: { "functions" => build_tools_array(phase: phase) }
          )

          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] ✅ Continuation call completed"
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 📊 New response has #{response[:tool_calls]&.length || 0} tool calls"

          # Track each continuation response to show LLM's reasoning after seeing function results
          # Build a summary of what functions were just executed for the rendered prompt
          function_summary = tool_calls.map { |tc| tc[:function_name] }.join(", ")
          continuation_prompt = "Function results for: #{function_summary}"

          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 📝 Tracking continuation response (iteration #{iteration})"
          track_llm_response(response, rendered_prompt: continuation_prompt)
        end

        if iteration >= max_iterations && response[:tool_calls].present?
          @logger.warn "[TaskAgentRuntimeService::OpenaiResponses] ⚠️  Max function call iterations (#{max_iterations}) reached"
        end

        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🏁 Function call loop completed after #{iteration} iterations"
        response
      end

      # Execute function calls and build input items for continuation
      #
      # @param tool_calls [Array<Hash>] tool calls from the API
      # @return [Array<Hash>] input items with function_call and function_call_output pairs
      def execute_function_calls_and_build_input(tool_calls)
        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🔨 Building input items from #{tool_calls.length} tool calls"

        input_items = []

        tool_calls.each_with_index do |tool_call, index|
          function_name = tool_call[:function_name]
          arguments = tool_call[:arguments]
          call_id = tool_call[:id]

          @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 🔧 [#{index+1}/#{tool_calls.length}] Executing: #{function_name}"
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses]   📝 Arguments: #{arguments.inspect[0..200]}"
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses]   🆔 Call ID: #{call_id}"

          # Execute the function (planning or regular)
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses]   ⚙️  Determining function type..."
          result = if planning_function?(function_name)
            @logger.info "[TaskAgentRuntimeService::OpenaiResponses]   🎯 Planning function detected"
            execute_planning_function(function_name, arguments)
          else
            @logger.info "[TaskAgentRuntimeService::OpenaiResponses]   🔨 Regular function detected"
            execute_regular_function(function_name, arguments)
          end

          @logger.info "[TaskAgentRuntimeService::OpenaiResponses]   ✅ Function executed, result: #{result.inspect[0..200]}"

          # Track the function call
          @current_iteration_function_calls << { name: function_name, arguments: arguments, result: result }

          # Build input items for API continuation (function_call + function_call_output pairs)
          # Note: function_call uses call_id (not id), function_call_output also uses call_id
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses]   📦 Building input items for continuation..."
          input_items << {
            type: "function_call",
            call_id: call_id,
            name: function_name,
            arguments: arguments.to_json
          }
          input_items << {
            type: "function_call_output",
            call_id: call_id,
            output: result.to_json
          }
          @logger.info "[TaskAgentRuntimeService::OpenaiResponses]   ✅ Input items built (total: #{input_items.length})"
        end

        @logger.info "[TaskAgentRuntimeService::OpenaiResponses] 📦 Total input items built: #{input_items.length}"
        input_items
      end

      # Execute a regular (non-planning) function
      #
      # @param function_name [String] the function name
      # @param arguments [Hash] the function arguments
      # @return [Hash] the function result
      def execute_regular_function(function_name, arguments)
        func_def = task_agent.function_definitions.find_by(name: function_name)
        unless func_def
          @logger.error "[TaskAgentRuntimeService::OpenaiResponses] Function not found: #{function_name}"
          return { error: "Function not found: #{function_name}" }
        end

        result = execute_function(func_def, arguments)
        result[:success?] ? result[:result] : { error: result[:error] }
      end
    end
  end
end
