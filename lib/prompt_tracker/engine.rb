module PromptTracker
  class Engine < ::Rails::Engine
    isolate_namespace PromptTracker

    initializer "prompt_tracker.assets.precompile" do |app|
      app.config.assets.precompile += %w[
        prompt_tracker/application.js
        prompt_tracker/application.css
        prompt_tracker/controllers/application.js
        prompt_tracker/controllers/index.js
        prompt_tracker/controllers/playground_controller.js
        prompt_tracker/controllers/assistant_playground_controller.js
        prompt_tracker/controllers/modal_fix_controller.js
        prompt_tracker/controllers/tooltip_controller.js
        prompt_tracker/controllers/patterns_controller.js
        prompt_tracker/controllers/model_config_controller.js
        prompt_tracker/controllers/evaluator_configs_controller.js
        prompt_tracker/controllers/tags_controller.js
        prompt_tracker/controllers/template_variables_controller.js
        prompt_tracker/controllers/evaluator_edit_controller.js
        prompt_tracker/controllers/evaluator_edit_form_controller.js
        prompt_tracker/controllers/pattern_match_controller.js
        prompt_tracker/controllers/accordion_state_controller.js
        prompt_tracker/controllers/column_visibility_controller.js
        prompt_tracker/controllers/resizable_columns_controller.js
        prompt_tracker/controllers/prompt_search_controller.js
        prompt_tracker/turbo_streams/close_modal.js
        prompt_tracker/controllers/run_test_modal_controller.js
        prompt_tracker/controllers/syntax_highlighter_controller.js
        prompt_tracker/controllers/pattern_match_form_controller.js
        prompt_tracker/controllers/batch_select_controller.js
        prompt_tracker/controllers/file_management_controller.js
        prompt_tracker/controllers/function_editor_controller.js
        prompt_tracker/controllers/generate_prompt_controller.js
        prompt_tracker/controllers/conversation_controller.js
        prompt_tracker/controllers/test_mode_controller.js
        prompt_tracker/controllers/tools_config_controller.js
        prompt_tracker/controllers/resizable_columns_controller.js
        prompt_tracker/controllers/lazy_edit_modal_controller.js
        prompt_tracker/controllers/playground_ui_controller.js
        prompt_tracker/controllers/playground_editor_controller.js
        prompt_tracker/controllers/playground_model_config_controller.js
        prompt_tracker/controllers/playground_coordinator_controller.js
        prompt_tracker/controllers/playground_preview_controller.js
        prompt_tracker/controllers/playground_save_controller.js
        prompt_tracker/controllers/playground_sync_controller.js
        prompt_tracker/controllers/playground_response_schema_controller.js
        prompt_tracker/controllers/playground_file_search_controller.js
        prompt_tracker/controllers/playground_functions_controller.js
        prompt_tracker/controllers/playground_tools_controller.js
        prompt_tracker/controllers/playground_generate_prompt_controller.js
        prompt_tracker/controllers/playground_prompt_editor_controller.js
        prompt_tracker/controllers/playground_variables_controller.js
        prompt_tracker/controllers/playground_conversation_controller.js
      ]
    end
    # # Make engine JS available to Sprockets (so importmap can find it)
    initializer "prompt_tracker.assets" do |app|
      app.config.assets.paths << root.join("app/javascript")
    end
    # Register importmap configuration
    initializer "prompt_tracker.importmap", before: "importmap" do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << root.join("config/importmap.rb")
        # Add cache sweeper for development
        app.config.importmap.cache_sweepers << root.join("app/javascript")
      end
    end



    # Include Turbo for real-time updates
    config.to_prepare do
      # Make Turbo helpers available in the engine
      ActiveSupport.on_load(:action_controller_base) do
        helper Turbo::StreamsHelper if defined?(Turbo::StreamsHelper)
      end
    end
  end
end
