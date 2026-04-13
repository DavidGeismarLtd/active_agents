// Manual controller registration - works with any JS pipeline (importmap, Webpacker, Sprockets)
// Uses bare specifiers resolved by importmap (either importmap-rails gem or native browser importmap)
import { application } from "prompt_tracker/controllers/application"

import AgentChatController from "prompt_tracker/controllers/agent_chat_controller"
import AgentTypeSelectorController from "prompt_tracker/controllers/agent_type_selector_controller"
import ApiKeyController from "prompt_tracker/controllers/api_key_controller"
import AssistantChatbotController from "prompt_tracker/controllers/assistant_chatbot_controller"
import BatchSelectController from "prompt_tracker/controllers/batch_select_controller"
import ColumnVisibilityController from "prompt_tracker/controllers/column_visibility_controller"
import EvaluatorConfigFormController from "prompt_tracker/controllers/evaluator_config_form_controller"
import EvaluatorConfigsController from "prompt_tracker/controllers/evaluator_configs_controller"
import EvaluatorEditController from "prompt_tracker/controllers/evaluator_edit_controller"
import EvaluatorEditFormController from "prompt_tracker/controllers/evaluator_edit_form_controller"
import FileManagementController from "prompt_tracker/controllers/file_management_controller"
import FunctionAiGeneratorController from "prompt_tracker/controllers/function_ai_generator_controller"
import FunctionCodeTemplatesController from "prompt_tracker/controllers/function_code_templates_controller"
import FunctionEditorController from "prompt_tracker/controllers/function_editor_controller"
import FunctionLanguageSwitcherController from "prompt_tracker/controllers/function_language_switcher_controller"
import FunctionParametersExamplesController from "prompt_tracker/controllers/function_parameters_examples_controller"
import FunctionTestController from "prompt_tracker/controllers/function_test_controller"
import LazyEditModalController from "prompt_tracker/controllers/lazy_edit_modal_controller"
import LinkedFiltersController from "prompt_tracker/controllers/linked_filters_controller"
import ModalFixController from "prompt_tracker/controllers/modal_fix_controller"
import MonacoEditorController from "prompt_tracker/controllers/monaco_editor_controller"
import PatternMatchFormController from "prompt_tracker/controllers/pattern_match_form_controller"
import PatternsController from "prompt_tracker/controllers/patterns_controller"
import PlaygroundConversationController from "prompt_tracker/controllers/playground_conversation_controller"
import PlaygroundFileSearchController from "prompt_tracker/controllers/playground_file_search_controller"
import PlaygroundFunctionsController from "prompt_tracker/controllers/playground_functions_controller"
import PlaygroundGeneratePromptController from "prompt_tracker/controllers/playground_generate_prompt_controller"
import PlaygroundModelConfigController from "prompt_tracker/controllers/playground_model_config_controller"
import PlaygroundPreviewController from "prompt_tracker/controllers/playground_preview_controller"
import PlaygroundPromptEditorController from "prompt_tracker/controllers/playground_prompt_editor_controller"
import PlaygroundResponseSchemaController from "prompt_tracker/controllers/playground_response_schema_controller"
import PlaygroundSaveController from "prompt_tracker/controllers/playground_save_controller"
import PlaygroundSyncController from "prompt_tracker/controllers/playground_sync_controller"
import PlaygroundSyncVisibilityController from "prompt_tracker/controllers/playground_sync_visibility_controller"
import PlaygroundToolsController from "prompt_tracker/controllers/playground_tools_controller"
import PlaygroundUiController from "prompt_tracker/controllers/playground_ui_controller"
import PlaygroundVariablesController from "prompt_tracker/controllers/playground_variables_controller"
import PromptSearchController from "prompt_tracker/controllers/prompt_search_controller"
import ResizableColumnsController from "prompt_tracker/controllers/resizable_columns_controller"
import RunTestModalController from "prompt_tracker/controllers/run_test_modal_controller"
import SyntaxHighlighterController from "prompt_tracker/controllers/syntax_highlighter_controller"
import TagsController from "prompt_tracker/controllers/tags_controller"
import TaskTimelineController from "prompt_tracker/controllers/task_timeline_controller"
import TemplateVariablesController from "prompt_tracker/controllers/template_variables_controller"
import TestModeController from "prompt_tracker/controllers/test_mode_controller"
import TooltipController from "prompt_tracker/controllers/tooltip_controller"

application.register("agent-chat", AgentChatController)
application.register("agent-type-selector", AgentTypeSelectorController)
application.register("api-key", ApiKeyController)
application.register("assistant-chatbot", AssistantChatbotController)
application.register("batch-select", BatchSelectController)
application.register("column-visibility", ColumnVisibilityController)
application.register("evaluator-config-form", EvaluatorConfigFormController)
application.register("evaluator-configs", EvaluatorConfigsController)
application.register("evaluator-edit", EvaluatorEditController)
application.register("evaluator-edit-form", EvaluatorEditFormController)
application.register("file-management", FileManagementController)
application.register("function-ai-generator", FunctionAiGeneratorController)
application.register("function-code-templates", FunctionCodeTemplatesController)
application.register("function-editor", FunctionEditorController)
application.register("function-language-switcher", FunctionLanguageSwitcherController)
application.register("function-parameters-examples", FunctionParametersExamplesController)
application.register("function-test", FunctionTestController)
application.register("lazy-edit-modal", LazyEditModalController)
application.register("linked-filters", LinkedFiltersController)
application.register("modal-fix", ModalFixController)
application.register("monaco-editor", MonacoEditorController)
application.register("pattern-match-form", PatternMatchFormController)
application.register("patterns", PatternsController)
application.register("playground-conversation", PlaygroundConversationController)
application.register("playground-file-search", PlaygroundFileSearchController)
application.register("playground-functions", PlaygroundFunctionsController)
application.register("playground-generate-prompt", PlaygroundGeneratePromptController)
application.register("playground-model-config", PlaygroundModelConfigController)
application.register("playground-preview", PlaygroundPreviewController)
application.register("playground-prompt-editor", PlaygroundPromptEditorController)
application.register("playground-response-schema", PlaygroundResponseSchemaController)
application.register("playground-save", PlaygroundSaveController)
application.register("playground-sync", PlaygroundSyncController)
application.register("playground-sync-visibility", PlaygroundSyncVisibilityController)
application.register("playground-tools", PlaygroundToolsController)
application.register("playground-ui", PlaygroundUiController)
application.register("playground-variables", PlaygroundVariablesController)
application.register("prompt-search", PromptSearchController)
application.register("resizable-columns", ResizableColumnsController)
application.register("run-test-modal", RunTestModalController)
application.register("syntax-highlighter", SyntaxHighlighterController)
application.register("tags", TagsController)
application.register("task-timeline", TaskTimelineController)
application.register("template-variables", TemplateVariablesController)
application.register("test-mode", TestModeController)
application.register("tooltip", TooltipController)
