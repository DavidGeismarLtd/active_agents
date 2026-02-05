# API Capabilities Refactoring - Product Requirements Document

**Version:** 1.0
**Date:** 2026-02-05
**Status:** Draft
**Author:** PromptTracker Team

---

## 1. Executive Summary

### 1.1 Current Problem Statement

The PromptTracker playground currently has tool support configuration scattered across multiple layers:

**Problem 1: Duplication and Inconsistency**
- Tool capabilities are defined in the **user's initializer** (`test/dummy/config/initializers/prompt_tracker.rb`)
- Only the Responses API has `capabilities: [:web_search, :file_search, :code_interpreter, :functions]` defined
- Chat Completions and Assistants APIs have **no capabilities listed**, even though they support tools according to OpenAI documentation
- This causes the tools panel to only appear for Responses API, hiding tool support from other APIs

**Problem 2: Wrong Separation of Concerns**
- The **engine** should define "what each provider/API can do" (capabilities matrix)
- The **initializer** should define "which providers/APIs/models are available to users" (configuration)
- Currently, both concerns are mixed in the initializer

**Problem 3: Artificial Distinction**
- The code treats "built-in tools" (web_search, file_search, code_interpreter) differently from "custom functions"
- This creates unnecessary complexity when both are just tool symbols that map to UI partials
- The distinction between `builtin_and_custom` vs `custom_only` adds cognitive overhead without clear benefit

**Problem 4: Hardcoded Partial Rendering**
- Configuration panels are hardcoded in the view:
  ```erb
  <%= render 'prompt_tracker/testing/playground/response_api_tools/file_search_configuration_panel', ... %>
  <%= render 'prompt_tracker/testing/playground/response_api_tools/functions_configuration_panel', ... %>
  ```
- Adding a new tool requires editing multiple files instead of following a convention

### 1.2 Proposed Solution

Create a centralized **`PromptTracker::ApiCapabilities`** service module that:

1. **Defines a capability matrix** in the engine code (single source of truth)
2. **Returns a flat array of tool symbols** for any provider/API combination
3. **Enables convention-based partial rendering** (tool symbol → partial name)
4. **Removes the initializer's responsibility** for defining capabilities

**Key Design Decision:**
- Use a **flat array of tool symbols** instead of categorizing tools as "builtin" vs "custom"
- Map each symbol to a partial by convention: `:web_search` → `web_search_configuration_panel.html.erb`
- Keep tool metadata (name, description, icon) in `Configuration#builtin_tools` (unchanged)

### 1.3 Expected Benefits and Impact

**✅ Benefits:**
1. **Correctness** - All APIs that support tools will show the tools panel
2. **Single Source of Truth** - Capabilities defined once in engine code
3. **Easier Maintenance** - Update engine when OpenAI changes APIs, not user initializers
4. **Convention Over Configuration** - Adding new tools requires: symbol + partial + metadata
5. **Simpler Mental Model** - No distinction between "builtin" and "custom" tools
6. **Future-Proof** - Easy to add new providers (Anthropic, Google) and their tool support

**📊 Impact:**
- **Breaking Change:** Remove `capabilities` from initializer API configs (migration guide provided)
- **Files Modified:** ~8 files (1 new service, 3 views, 2 helpers, 1 config, 1 test)
- **Risk Level:** Low (well-contained change with clear rollback path)
- **User Impact:** Positive (more features visible, better UX)

---

## 2. Technical Specification

### 2.1 API Design

#### 2.1.1 Core Service Module

**File:** `lib/prompt_tracker/api_capabilities.rb`

```ruby
module PromptTracker
  # Centralized API capability definitions for all LLM providers.
  # This module serves as the single source of truth for what each
  # provider/API combination supports.
  #
  # @example Check if an API supports tools
  #   PromptTracker::ApiCapabilities.supports_tools?(:openai, :chat_completions)
  #   # => true
  #
  # @example Get available tools for an API
  #   PromptTracker::ApiCapabilities.tools_for(:openai, :responses)
  #   # => [:web_search, :file_search, :code_interpreter, :functions]
  #
  module ApiCapabilities
    # Capability matrix defining what each provider/API supports.
    # Structure: provider → api → capabilities hash
    CAPABILITIES = {
      openai: {
        chat_completions: {
          tools: [:functions],
          features: [:streaming, :vision, :structured_output, :function_calling]
        },
        responses: {
          tools: [:web_search, :file_search, :code_interpreter, :functions],
          features: [:streaming, :vision, :structured_output, :function_calling, :conversation_state]
        },
        assistants: {
          tools: [:code_interpreter, :file_search, :functions],
          features: [:threads, :runs, :vision, :function_calling, :file_uploads]
        }
      },
      anthropic: {
        messages: {
          tools: [:functions],
          features: [:streaming, :vision, :structured_output, :function_calling]
        }
      }
      # Future providers can be added here (Google, Cohere, etc.)
    }.freeze

    # Get available tools for a provider/API combination.
    #
    # @param provider [Symbol, String] the provider key (e.g., :openai, :anthropic)
    # @param api [Symbol, String] the API key (e.g., :chat_completions, :responses)
    # @return [Array<Symbol>] array of tool symbols (e.g., [:web_search, :functions])
    #
    # @example
    #   ApiCapabilities.tools_for(:openai, :chat_completions)
    #   # => [:functions]
    #
    #   ApiCapabilities.tools_for(:openai, :responses)
    #   # => [:web_search, :file_search, :code_interpreter, :functions]
    #
    def self.tools_for(provider, api)
      CAPABILITIES.dig(provider.to_sym, api.to_sym, :tools) || []
    end

    # Check if a provider/API supports any tools.
    #
    # @param provider [Symbol, String] the provider key
    # @param api [Symbol, String] the API key
    # @return [Boolean] true if the API supports at least one tool
    #
    # @example
    #   ApiCapabilities.supports_tools?(:openai, :chat_completions)
    #   # => true
    #
    #   ApiCapabilities.supports_tools?(:openai, :embeddings)
    #   # => false
    #
    def self.supports_tools?(provider, api)
      tools_for(provider, api).any?
    end

    # Check if a provider/API supports a specific feature.
    #
    # @param provider [Symbol, String] the provider key
    # @param api [Symbol, String] the API key
    # @param feature [Symbol] the feature to check (e.g., :streaming, :vision)
    # @return [Boolean] true if the feature is supported
    #
    # @example
    #   ApiCapabilities.supports_feature?(:openai, :chat_completions, :streaming)
    #   # => true
    #
    def self.supports_feature?(provider, api, feature)
      features = CAPABILITIES.dig(provider.to_sym, api.to_sym, :features) || []
      features.include?(feature.to_sym)
    end

    # Get all features supported by a provider/API.
    #
    # @param provider [Symbol, String] the provider key
    # @param api [Symbol, String] the API key
    # @return [Array<Symbol>] array of feature symbols
    #
    def self.features_for(provider, api)
      CAPABILITIES.dig(provider.to_sym, api.to_sym, :features) || []
    end
  end
end
```

#### 2.1.2 Updated Configuration Class

**File:** `lib/prompt_tracker/configuration.rb`

**Changes to `#tools_for_api` method:**

```ruby
# Get available tools for a specific provider and API combination.
# Delegates to ApiCapabilities for the capability matrix, then enriches
# with display metadata from builtin_tools.
#
# @param provider [Symbol] the provider key
# @param api [Symbol] the API key
# @return [Array<Hash>] array of tool hashes with :id, :name, :description, :icon, :configurable
def tools_for_api(provider, api)
  # Get tool symbols from ApiCapabilities (engine's capability matrix)
  tool_symbols = PromptTracker::ApiCapabilities.tools_for(provider, api)

  # Map each symbol to its display metadata
  tool_symbols.map do |tool_symbol|
    tool_metadata = builtin_tools[tool_symbol.to_sym]
    next unless tool_metadata

    {
      id: tool_symbol.to_s,
      name: tool_metadata[:name],
      description: tool_metadata[:description],
      icon: tool_metadata[:icon],
      configurable: tool_metadata[:configurable] == true
    }
  end.compact
end
```

**No changes needed to:**
- `#builtin_tools` - Still provides display metadata (name, description, icon)
- `#default_builtin_tools` - Still defines the default metadata hash

### 2.2 Tool Naming Conventions and Mapping Rules

#### 2.2.1 Tool Symbol → Partial Name Convention

**Convention:** `{tool_symbol}_configuration_panel.html.erb`

| Tool Symbol | Partial Path |
|-------------|--------------|
| `:web_search` | `app/views/prompt_tracker/testing/playground/response_api_tools/web_search_configuration_panel.html.erb` |
| `:file_search` | `app/views/prompt_tracker/testing/playground/response_api_tools/file_search_configuration_panel.html.erb` |
| `:code_interpreter` | `app/views/prompt_tracker/testing/playground/response_api_tools/code_interpreter_configuration_panel.html.erb` |
| `:functions` | `app/views/prompt_tracker/testing/playground/response_api_tools/functions_configuration_panel.html.erb` |

**Rules:**
1. Tool symbols use **snake_case** (`:web_search`, not `:webSearch`)
2. Partial names match the symbol exactly with `_configuration_panel.html.erb` suffix
3. Only tools with `configurable: true` in metadata will have partials rendered
4. Tools without configuration (like `:web_search`) don't need a partial

#### 2.2.2 Tool Metadata Structure

**Location:** `Configuration#default_builtin_tools`

```ruby
def default_builtin_tools
  {
    web_search: {
      name: "Web Search",
      description: "Search the web for current information",
      icon: "bi-globe",
      configurable: false  # No configuration panel needed
    },
    file_search: {
      name: "File Search",
      description: "Search through uploaded files",
      icon: "bi-file-earmark-search",
      configurable: true  # Has configuration panel for vector stores
    },
    code_interpreter: {
      name: "Code Interpreter",
      description: "Execute Python code for analysis",
      icon: "bi-code-slash",
      configurable: false  # No configuration panel needed
    },
    functions: {
      name: "Functions",
      description: "Define custom function schemas",
      icon: "bi-braces-asterisk",
      configurable: true  # Has configuration panel for function definitions
    }
  }
end
```

### 2.3 View Partial Naming Conventions

#### 2.3.1 Dynamic Partial Rendering

**File:** `app/views/prompt_tracker/testing/playground/_response_api_tools.html.erb`

**Before (hardcoded):**
```erb
<%# File Search Configuration Panel %>
<%= render 'prompt_tracker/testing/playground/response_api_tools/file_search_configuration_panel',
           file_search_config: file_search_config,
           enabled_tools_hash: enabled_tools_hash,
           tool_config: tool_config %>

<%# Functions Configuration Panel %>
<%= render 'prompt_tracker/testing/playground/response_api_tools/functions_configuration_panel',
           functions_config: functions_config,
           enabled_tools_hash: enabled_tools_hash,
           tool_config: tool_config %>
```

**After (convention-based):**
```erb
<%# Render configuration panels for configurable tools %>
<% available_tools.each do |tool| %>
  <% if tool[:configurable] %>
    <%# Convention: {tool_id}_configuration_panel.html.erb %>
    <% tool_config_data = tool_config.dig(tool[:id]) || {} %>
    <%= render "prompt_tracker/testing/playground/response_api_tools/#{tool[:id]}_configuration_panel",
               config: tool_config_data,
               enabled_tools_hash: enabled_tools_hash,
               tool_config: tool_config %>
  <% end %>
<% end %>
```

**Benefits:**
- Adding a new configurable tool only requires creating the partial
- No need to edit the main `_response_api_tools.html.erb` file
- Follows Rails convention over configuration principle

---

## 3. Implementation Plan

### 3.1 Phase 1: Create ApiCapabilities Service (Low Risk)

**Goal:** Add the new service without breaking existing functionality.

**Tasks:**
1. ✅ Create `lib/prompt_tracker/api_capabilities.rb` with capability matrix
2. ✅ Add comprehensive RSpec tests for the service
3. ✅ Verify all existing functionality still works (no changes to calling code yet)

**Files Created:**
- `lib/prompt_tracker/api_capabilities.rb`
- `spec/lib/prompt_tracker/api_capabilities_spec.rb`

**Acceptance Criteria:**
- [ ] All tests pass
- [ ] Service returns correct tool arrays for all provider/API combinations
- [ ] Service handles unknown providers/APIs gracefully (returns empty array)

### 3.2 Phase 2: Update Configuration to Use ApiCapabilities (Medium Risk)

**Goal:** Make `Configuration#tools_for_api` delegate to `ApiCapabilities`.

**Tasks:**
1. ✅ Update `Configuration#tools_for_api` to call `ApiCapabilities.tools_for`
2. ✅ Update existing Configuration specs to verify new behavior
3. ✅ Run full test suite to ensure no regressions

**Files Modified:**
- `lib/prompt_tracker/configuration.rb` (lines 365-382)
- `spec/lib/prompt_tracker/configuration_spec.rb` (add tests for `#tools_for_api`)

**Acceptance Criteria:**
- [ ] `Configuration#tools_for_api` returns same structure as before
- [ ] All existing tests pass
- [ ] New tests verify delegation to ApiCapabilities

### 3.3 Phase 3: Rename Folder Structure to Generic `tools/` (Low Risk)

**Goal:** Rename `response_api_tools/` to generic `tools/` folder to reflect that tools are not API-specific.

**Rationale:**
- Tools like `file_search` and `functions` work identically across Chat Completions, Responses, and Assistants APIs
- Current naming (`response_api_tools/`) is misleading and suggests API-specific behavior
- Generic naming enables reuse across all APIs and future providers

**Tasks:**
1. ✅ Rename folder: `response_api_tools/` → `tools/`
2. ✅ Rename main partial: `_response_api_tools.html.erb` → `_tools_panel.html.erb`
3. ✅ Update all partial render paths in views
4. ✅ Update Stimulus controller data-controller attributes

**Files to Rename:**
```bash
# Rename folder
mv app/views/prompt_tracker/testing/playground/response_api_tools \
   app/views/prompt_tracker/testing/playground/tools

# Rename main partial
mv app/views/prompt_tracker/testing/playground/_response_api_tools.html.erb \
   app/views/prompt_tracker/testing/playground/_tools_panel.html.erb
```

**Files Modified (update render paths):**
- `app/views/prompt_tracker/testing/playground/show.html.erb`
  - Change: `render 'response_api_tools'` → `render 'tools_panel'`
- `app/views/prompt_tracker/testing/playground/_tools_panel.html.erb`
  - Change: `render "prompt_tracker/testing/playground/response_api_tools/#{tool[:id]}_configuration_panel"`
  - To: `render "prompt_tracker/testing/playground/tools/#{tool[:id]}_configuration_panel"`

**Acceptance Criteria:**
- [ ] All partials render correctly from new `tools/` folder
- [ ] No broken partial references
- [ ] No visual regressions in playground UI

### 3.4 Phase 4: Update Views for Convention-Based Rendering (Medium Risk)

**Goal:** Replace hardcoded partial renders with dynamic convention-based rendering.

**Tasks:**
1. ✅ Update `_tools_panel.html.erb` to use dynamic partial rendering
2. ✅ Ensure all existing partials follow naming convention
3. ✅ Test in browser that all tools still render correctly

**Files Modified:**
- `app/views/prompt_tracker/testing/playground/_tools_panel.html.erb` (formerly `_response_api_tools.html.erb`)

**Files Verified (naming convention):**
- `app/views/prompt_tracker/testing/playground/tools/_file_search_configuration_panel.html.erb` ✅
- `app/views/prompt_tracker/testing/playground/tools/_functions_configuration_panel.html.erb` ✅

**Acceptance Criteria:**
- [ ] Tools panel renders correctly for all APIs
- [ ] Configuration panels show/hide based on tool selection
- [ ] No JavaScript errors in browser console

### 3.5 Phase 5: Refactor Stimulus Controllers (Medium Risk)

**Goal:** Split monolithic `tools_config_controller.js` into focused, single-responsibility controllers.

**Current Problem:**
- `tools_config_controller.js` is 793 lines handling everything (file search, functions, panels, modals)
- Violates Single Responsibility Principle
- Hard to maintain and test

**New Architecture:**
- `tools_panel_controller.js` - Show/hide tools panel based on API capabilities
- `file_search_tool_controller.js` - Manage file_search configuration (vector stores)
- `functions_tool_controller.js` - Manage custom functions configuration
- `playground_controller.js` - Orchestrate and collect configs from tool controllers

**Tasks:**
1. ✅ Create `tools_panel_controller.js` (handles tool visibility and rendering)
2. ✅ Create `file_search_tool_controller.js` (extract from `tools_config_controller.js`)
3. ✅ Create `functions_tool_controller.js` (extract from `tools_config_controller.js`)
4. ✅ Update `playground_controller.js` to delegate to tool controllers
5. ✅ Update view data-controller attributes
6. ✅ Delete old `tools_config_controller.js`
7. ✅ Test all tool interactions in browser

**Files Created:**
- `app/javascript/prompt_tracker/controllers/tools_panel_controller.js` (~100 lines)
- `app/javascript/prompt_tracker/controllers/file_search_tool_controller.js` (~200 lines)
- `app/javascript/prompt_tracker/controllers/functions_tool_controller.js` (~150 lines)

**Files Modified:**
- `app/javascript/prompt_tracker/controllers/playground_controller.js` (update `getToolConfig()`)
- `app/views/prompt_tracker/testing/playground/_tools_panel.html.erb` (update data-controller attributes)
- `app/views/prompt_tracker/testing/playground/tools/_file_search_configuration_panel.html.erb` (update data-controller)
- `app/views/prompt_tracker/testing/playground/tools/_functions_configuration_panel.html.erb` (update data-controller)

**Files Deleted:**
- `app/javascript/prompt_tracker/controllers/tools_config_controller.js` (793 lines → deleted)

**Acceptance Criteria:**
- [ ] Each controller has a single, clear responsibility
- [ ] Tool panels show/hide correctly when toggling checkboxes
- [ ] File search vector store management works
- [ ] Functions configuration works
- [ ] All tool configurations are collected correctly on save
- [ ] No JavaScript errors in console
- [ ] Total lines of code reduced (793 → ~450 across 3 focused controllers)

### 3.6 Phase 6: Remove Capabilities from Initializer (Breaking Change)

**Goal:** Clean up the initializer by removing the now-redundant `capabilities` arrays.

**Tasks:**
1. ✅ Update `test/dummy/config/initializers/prompt_tracker.rb` to remove `capabilities`
2. ✅ Add migration guide to CHANGELOG
3. ✅ Update documentation with new architecture

**Files Modified:**
- `test/dummy/config/initializers/prompt_tracker.rb` (lines 35-50)
- `CHANGELOG.md` (add breaking change notice)
- `README.md` or docs (update configuration examples)

**Migration Guide for Users:**

```ruby
# BEFORE (old initializer)
config.providers = {
  openai: {
    name: "OpenAI",
    apis: {
      responses: {
        name: "Responses",
        description: "Stateful conversations with built-in tools",
        capabilities: [:web_search, :file_search, :code_interpreter, :functions]  # ❌ Remove this
      }
    }
  }
}

# AFTER (new initializer)
config.providers = {
  openai: {
    name: "OpenAI",
    apis: {
      responses: {
        name: "Responses",
        description: "Stateful conversations with built-in tools"
        # ✅ No capabilities needed - defined in engine
      }
    }
  }
}
```

**Acceptance Criteria:**
- [ ] Initializer has no `capabilities` arrays
- [ ] Tools still appear correctly in playground
- [ ] Migration guide is clear and complete

### 3.7 Phase 7: Update View Data-Controller Attributes (Low Risk)

**Goal:** Update views to use new Stimulus controller architecture.

**Tasks:**
1. ✅ Update `_tools_panel.html.erb` to use `tools-panel` controller
2. ✅ Update file search partial to use `file-search-tool` controller
3. ✅ Update functions partial to use `functions-tool` controller
4. ✅ Remove old `tools-config` controller references

**Files Modified:**

**`app/views/prompt_tracker/testing/playground/_tools_panel.html.erb`:**
```erb
<%# Before %>
<div class="response-api-tools mt-3"
     data-controller="tools-config"
     data-playground-target="responseApiTools">

<%# After %>
<div class="tools-panel mt-3"
     data-controller="tools-panel"
     data-action="playground:api-changed->tools-panel#updateForApi">
```

**`app/views/prompt_tracker/testing/playground/tools/_file_search_configuration_panel.html.erb`:**
```erb
<%# Before %>
<div id="file-search-config"
     class="tool-config-panel mt-3 p-3 border rounded bg-light"
     data-tools-config-target="fileSearchPanel">

<%# After %>
<div id="file-search-config"
     class="tool-config-panel mt-3 p-3 border rounded bg-light"
     data-controller="file-search-tool"
     data-file-search-tool-target="panel">
```

**`app/views/prompt_tracker/testing/playground/tools/_functions_configuration_panel.html.erb`:**
```erb
<%# Before %>
<div id="functions-config"
     class="tool-config-panel mt-3 p-3 border rounded bg-light"
     data-tools-config-target="functionsPanel">

<%# After %>
<div id="functions-config"
     class="tool-config-panel mt-3 p-3 border rounded bg-light"
     data-controller="functions-tool"
     data-functions-tool-target="panel">
```

**Acceptance Criteria:**
- [ ] All Stimulus controllers connect properly
- [ ] Tool panels show/hide correctly
- [ ] No "controller not found" errors in console

### 3.8 Phase 8: Verify Integration (Low Risk)

**Goal:** Ensure all pieces work together correctly.

**Tasks:**
1. ✅ Verify `PlaygroundHelper#available_tools_for_provider` still works
2. ✅ Verify JavaScript `tools_by_api` data structure is correct
3. ✅ Test dynamic tool panel show/hide on API change
4. ✅ Test tool configuration collection on save

**Files Verified:**
- `app/helpers/prompt_tracker/playground_helper.rb` (lines 21-32) - No changes needed
- `app/views/prompt_tracker/testing/playground/_model_config_form.html.erb` (lines 35, 101-104) - No changes needed

**Acceptance Criteria:**
- [ ] Changing provider/API in playground updates tools panel correctly
- [ ] JavaScript receives correct `tools_by_api` data
- [ ] Tool configurations are saved correctly
- [ ] No console errors

---

## 4. Code Examples

### 4.1 Complete ApiCapabilities Service Class

**File:** `lib/prompt_tracker/api_capabilities.rb`
See section 2.1.1 for the complete implementation.

### 4.2 Controller Usage Example

**File:** `app/controllers/prompt_tracker/testing/playground_controller.rb`

No changes needed! The controller doesn't directly call `tools_for_api`. The helper methods handle it.

### 4.3 Helper Usage Example

**File:** `app/helpers/prompt_tracker/playground_helper.rb`

```ruby
module PromptTracker
  module PlaygroundHelper
    # Get available tools for the current provider and API.
    # This method remains unchanged - it delegates to Configuration,
    # which now delegates to ApiCapabilities.
    #
    # @param provider [Symbol, String] the provider key (defaults to current)
    # @param api [Symbol, String] the API key (defaults to current)
    # @return [Array<Hash>] list of available tools with id, name, description, icon
    def available_tools_for_provider(provider: nil, api: nil)
      provider ||= current_provider
      api ||= current_api

      # This calls Configuration#tools_for_api, which now uses ApiCapabilities
      PromptTracker.configuration.tools_for_api(provider.to_sym, api.to_sym)
    end

    # Check if the provider/API supports tools
    # This method can now be simplified to use ApiCapabilities directly
    #
    # @param provider [String] the provider name
    # @param api [String] the API name
    # @return [Boolean] true if API supports tools
    def provider_supports_tools?(provider: nil, api: nil)
      provider ||= current_provider
      api ||= current_api

      # Option 1: Use existing method (works, but less efficient)
      # available_tools_for_provider(provider: provider, api: api).any?

      # Option 2: Use ApiCapabilities directly (more efficient)
      PromptTracker::ApiCapabilities.supports_tools?(provider.to_sym, api.to_sym)
    end
  end
end
```

### 4.4 View Code Example - Dynamic Partial Rendering

**File:** `app/views/prompt_tracker/testing/playground/_tools_panel.html.erb` (renamed from `_response_api_tools.html.erb`)

```erb
<%#
  Tools Panel
  Shown when any API supports tools (Chat Completions, Responses, Assistants, etc.)

  Local variables:
    - available_tools: Array of tool hashes from Configuration#tools_for_api
    - enabled_tools: Hash with tool configs
    - tool_config: Hash with detailed tool configuration
%>

<%
  available_tools ||= []
  # Handle both array format (legacy) and hash format (new)
  if enabled_tools.is_a?(Array)
    enabled_tools_hash = enabled_tools.each_with_object({}) { |t, h| h[t.to_s] = true }
  else
    enabled_tools_hash = enabled_tools || {}
  end
  tool_config ||= @version&.model_config&.dig('tool_config') || {}
%>

<div class="tools-panel mt-3"
     data-controller="tools-panel"
     data-action="playground:api-changed->tools-panel#updateForApi"
     data-playground-target="toolsContainer">
  <label class="form-label">
    <i class="bi bi-tools"></i> Tools
    <span class="badge bg-info ms-1">Beta</span>
  </label>
  <div class="form-text mb-2">
    Enable tools for this API. Tools allow the model to search the web,
    analyze files, execute code, and call custom functions.
  </div>

  <%# Tool Cards - Loop through available tools %>
  <div class="row g-2" data-tools-panel-target="content">
    <% available_tools.each do |tool| %>
      <%
        is_enabled = enabled_tools_hash[tool[:id].to_s].present?
        card_class = is_enabled ? 'active' : ''
        is_configurable = tool[:configurable] == true
      %>
      <div class="col-md-3">
        <label class="card tool-card p-3 h-100 position-relative <%= card_class %>"
               for="tool_<%= tool[:id] %>">
          <input class="d-none"
                 type="checkbox"
                 id="tool_<%= tool[:id] %>"
                 value="<%= tool[:id] %>"
                 data-tool-id="<%= tool[:id] %>"
                 data-configurable="<%= is_configurable %>"
                 data-action="change->tools-panel#onToolToggle"
                 <%= 'checked' if is_enabled %>>
          <i class="bi bi-check-circle-fill check-indicator"></i>
          <div class="text-center">
            <i class="bi <%= tool[:icon] %> tool-icon d-block mb-2"></i>
            <strong class="d-block" style="font-size: 0.85rem;"><%= tool[:name] %></strong>
            <small class="text-muted" style="font-size: 0.7rem;"><%= tool[:description] %></small>
          </div>
        </label>
      </div>
    <% end %>
  </div>

  <%# Configuration Panels - Convention-based rendering from generic tools/ folder %>
  <% available_tools.each do |tool| %>
    <% if tool[:configurable] %>
      <%# Convention: tools/{tool_id}_configuration_panel.html.erb %>
      <% tool_config_data = tool_config.dig(tool[:id]) || {} %>
      <%= render "prompt_tracker/testing/playground/tools/#{tool[:id]}_configuration_panel",
                 config: tool_config_data,
                 enabled_tools_hash: enabled_tools_hash,
                 tool_config: tool_config %>
    <% end %>
  <% end %>

  <%# Modals (if any tools need them) %>
  <% if available_tools.any? { |t| t[:id] == 'file_search' } %>
    <%= render 'prompt_tracker/testing/playground/tools/create_vector_store_modal' %>
    <%= render 'prompt_tracker/testing/playground/tools/vector_store_files_modal' %>
  <% end %>

  <% if available_tools.empty? %>
    <div class="alert alert-secondary py-2" data-tools-panel-target="noToolsAlert">
      <i class="bi bi-info-circle"></i>
      No tools available for this API.
    </div>
  <% end %>
</div>
```

**Key Changes:**
1. ✅ Renamed file: `_response_api_tools.html.erb` → `_tools_panel.html.erb`
2. ✅ Updated data-controller: `tools-config` → `tools-panel`
3. ✅ Updated partial paths: `response_api_tools/` → `tools/`
4. ✅ Simplified data-action: removed playground controller actions, delegated to tools-panel
5. ✅ Updated targets: `responseApiToolsContent` → `content` (scoped to tools-panel controller)

### 4.5 Stimulus Controller Architecture Refactoring

**Current Problem:** The `tools_config_controller.js` (793 lines!) violates Single Responsibility Principle by handling:
- File search vector store management
- Functions configuration
- Panel visibility
- Tool checkbox toggling
- Modal management

**Proposed Architecture:** Separate concerns into focused controllers:

#### 4.5.1 Tools Panel Controller (NEW)

**File:** `app/javascript/prompt_tracker/controllers/tools_panel_controller.js` (NEW)

**Responsibility:** Show/hide tools panel based on provider/API selection

```javascript
import { Controller } from "@hotwired/stimulus"

/**
 * Tools Panel Controller
 * Manages visibility of the tools panel based on API capabilities.
 * This controller determines WHAT tools to show, not HOW to configure them.
 */
export default class extends Controller {
  static targets = ["container", "content", "noToolsAlert"]

  /**
   * Show/hide tools panel when API changes
   * Called by playground_controller via custom event
   */
  updateForApi(event) {
    const { tools } = event.detail
    const hasTools = tools && tools.length > 0

    if (this.hasContainerTarget) {
      this.containerTarget.style.display = hasTools ? '' : 'none'
    }

    if (hasTools && this.hasContentTarget) {
      this.renderToolCards(tools)
    }

    if (this.hasNoToolsAlertTarget) {
      this.noToolsAlertTarget.style.display = hasTools ? 'none' : ''
    }
  }

  /**
   * Render tool selection cards dynamically
   */
  renderToolCards(tools) {
    if (!this.hasContentTarget) return

    const container = this.contentTarget
    container.innerHTML = ''

    tools.forEach(tool => {
      const col = document.createElement('div')
      col.className = 'col-md-3'

      col.innerHTML = `
        <label class="card tool-card p-3 h-100 position-relative"
               for="tool_${tool.id}">
          <input class="d-none"
                 type="checkbox"
                 id="tool_${tool.id}"
                 value="${tool.id}"
                 data-tool-id="${tool.id}"
                 data-configurable="${tool.configurable}"
                 data-action="change->tools-panel#onToolToggle">
          <i class="bi bi-check-circle-fill check-indicator"></i>
          <div class="text-center">
            <i class="bi ${tool.icon} tool-icon d-block mb-2"></i>
            <strong class="d-block" style="font-size: 0.85rem;">${tool.name}</strong>
            <small class="text-muted" style="font-size: 0.7rem;">${tool.description}</small>
          </div>
        </label>
      `

      container.appendChild(col)
    })
  }

  /**
   * Handle tool checkbox toggle - dispatch event for tool-specific controllers
   */
  onToolToggle(event) {
    const checkbox = event.target
    const toolId = checkbox.dataset.toolId
    const isConfigurable = checkbox.dataset.configurable === 'true'

    // Update card visual state
    const card = checkbox.closest('.tool-card')
    if (card) {
      card.classList.toggle('active', checkbox.checked)
    }

    // Dispatch event for tool-specific controllers to listen
    this.dispatch('tool-toggled', {
      detail: {
        toolId: toolId,
        enabled: checkbox.checked,
        configurable: isConfigurable
      }
    })
  }
}
```

#### 4.5.2 File Search Tool Controller (NEW)

**File:** `app/javascript/prompt_tracker/controllers/file_search_tool_controller.js` (NEW)

**Responsibility:** Manage file_search tool configuration (vector stores)

```javascript
import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

/**
 * File Search Tool Controller
 * Manages file_search tool configuration including vector store selection.
 * Only active when file_search tool is enabled.
 */
export default class extends Controller {
  static targets = [
    "panel",
    "vectorStoreSelect",
    "selectedVectorStores",
    "vectorStoreCount",
    "addButton",
    "error"
  ]

  static MAX_VECTOR_STORES = 2

  connect() {
    this.vectorStoresLoaded = false
    // Listen for tool toggle events
    this.element.addEventListener('tools-panel:tool-toggled', this.handleToolToggle.bind(this))
  }

  disconnect() {
    this.element.removeEventListener('tools-panel:tool-toggled', this.handleToolToggle.bind(this))
  }

  /**
   * Handle tool toggle event from tools-panel controller
   */
  handleToolToggle(event) {
    const { toolId, enabled } = event.detail

    if (toolId === 'file_search') {
      this.updatePanelVisibility(enabled)

      if (enabled && !this.vectorStoresLoaded) {
        this.loadVectorStores()
      }
    }
  }

  /**
   * Show/hide configuration panel
   */
  updatePanelVisibility(show) {
    if (this.hasPanelTarget) {
      this.panelTarget.classList.toggle('show', show)
    }
  }

  /**
   * Load vector stores from API
   */
  async loadVectorStores() {
    // ... (existing implementation from tools_config_controller.js)
  }

  /**
   * Add vector store
   */
  addVectorStore() {
    // ... (existing implementation)
  }

  /**
   * Remove vector store
   */
  removeVectorStore(event) {
    // ... (existing implementation)
  }

  /**
   * Get current configuration
   */
  getConfig() {
    const vectorStores = []
    if (this.hasSelectedVectorStoresTarget) {
      this.selectedVectorStoresTarget.querySelectorAll('[data-vector-store-id]').forEach(badge => {
        vectorStores.push({
          id: badge.dataset.vectorStoreId,
          name: badge.dataset.vectorStoreName
        })
      })
    }

    return vectorStores.length > 0 ? {
      vector_store_ids: vectorStores.slice(0, this.constructor.MAX_VECTOR_STORES).map(vs => vs.id),
      vector_stores: vectorStores.slice(0, this.constructor.MAX_VECTOR_STORES)
    } : null
  }
}
```

#### 4.5.3 Functions Tool Controller (NEW)

**File:** `app/javascript/prompt_tracker/controllers/functions_tool_controller.js` (NEW)

**Responsibility:** Manage custom functions configuration

```javascript
import { Controller } from "@hotwired/stimulus"

/**
 * Functions Tool Controller
 * Manages custom function definitions.
 * Only active when functions tool is enabled.
 */
export default class extends Controller {
  static targets = [
    "panel",
    "functionsList",
    "functionItem",
    "noFunctionsMessage"
  ]

  connect() {
    // Listen for tool toggle events
    this.element.addEventListener('tools-panel:tool-toggled', this.handleToolToggle.bind(this))
  }

  disconnect() {
    this.element.removeEventListener('tools-panel:tool-toggled', this.handleToolToggle.bind(this))
  }

  /**
   * Handle tool toggle event
   */
  handleToolToggle(event) {
    const { toolId, enabled } = event.detail

    if (toolId === 'functions') {
      this.updatePanelVisibility(enabled)
    }
  }

  /**
   * Show/hide configuration panel
   */
  updatePanelVisibility(show) {
    if (this.hasPanelTarget) {
      this.panelTarget.classList.toggle('show', show)
    }
  }

  /**
   * Add a new function
   */
  addFunction() {
    // ... (existing implementation from tools_config_controller.js)
  }

  /**
   * Remove a function
   */
  removeFunction(event) {
    // ... (existing implementation)
  }

  /**
   * Get current configuration
   */
  getConfig() {
    const functions = []

    this.functionItemTargets.forEach(item => {
      const nameInput = item.querySelector('[data-function-name]')
      const descInput = item.querySelector('[data-function-description]')
      const paramsInput = item.querySelector('[data-function-parameters]')
      const strictInput = item.querySelector('[data-function-strict]')

      const name = nameInput?.value?.trim()
      if (!name) return

      let parameters = {}
      try {
        const paramsText = paramsInput?.value?.trim()
        if (paramsText) parameters = JSON.parse(paramsText)
      } catch (e) {
        console.warn('Invalid JSON in function parameters:', e)
      }

      functions.push({
        name: name,
        description: descInput?.value?.trim() || '',
        parameters: parameters,
        strict: strictInput?.checked || false
      })
    })

    return functions.length > 0 ? functions : null
  }
}
```

#### 4.5.4 Updated Playground Controller

**File:** `app/javascript/prompt_tracker/controllers/playground_controller.js`

**Changes:** Delegate to tools-panel controller instead of managing tools directly

```javascript
// Update API-specific UI elements (description, tools, etc.)
updateApiSpecificUI(apiConfig, tools = []) {
  // Update API description
  if (this.hasApiDescriptionTarget) {
    this.apiDescriptionTarget.textContent = apiConfig?.description || 'Select an API endpoint'
  }

  // Dispatch event for tools-panel controller to handle
  this.dispatch('api-changed', {
    detail: {
      provider: this.modelProviderTarget.value,
      api: this.modelApiTarget.value,
      tools: tools
    }
  })
}

// Collect tool configuration from tool-specific controllers
getToolConfig() {
  const config = {
    enabled_tools: [],
    tool_config: {}
  }

  // Get enabled tools from checkboxes
  const checkboxes = this.element.querySelectorAll('input[type="checkbox"][data-tool-id]:checked')
  checkboxes.forEach(cb => config.enabled_tools.push(cb.dataset.toolId))

  // Get file_search config from file-search-tool controller
  const fileSearchController = this.application.getControllerForElementAndIdentifier(
    this.element.querySelector('[data-controller~="file-search-tool"]'),
    'file-search-tool'
  )
  if (fileSearchController) {
    const fileSearchConfig = fileSearchController.getConfig()
    if (fileSearchConfig) config.tool_config.file_search = fileSearchConfig
  }

  // Get functions config from functions-tool controller
  const functionsController = this.application.getControllerForElementAndIdentifier(
    this.element.querySelector('[data-controller~="functions-tool"]'),
    'functions-tool'
  )
  if (functionsController) {
    const functionsConfig = functionsController.getConfig()
    if (functionsConfig) config.tool_config.functions = functionsConfig
  }

  return config
}
```

**Key Point:** The JavaScript architecture now follows Single Responsibility Principle with clear separation of concerns!

---

## 5. Testing Strategy

### 5.1 RSpec Test Plan for ApiCapabilities Service

**File:** `spec/lib/prompt_tracker/api_capabilities_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe ApiCapabilities do
    describe ".tools_for" do
      context "with OpenAI provider" do
        it "returns functions for chat_completions API" do
          tools = described_class.tools_for(:openai, :chat_completions)
          expect(tools).to eq([:functions])
        end

        it "returns all tools for responses API" do
          tools = described_class.tools_for(:openai, :responses)
          expect(tools).to contain_exactly(:web_search, :file_search, :code_interpreter, :functions)
        end

        it "returns builtin tools and functions for assistants API" do
          tools = described_class.tools_for(:openai, :assistants)
          expect(tools).to contain_exactly(:code_interpreter, :file_search, :functions)
        end
      end

      context "with Anthropic provider" do
        it "returns functions for messages API" do
          tools = described_class.tools_for(:anthropic, :messages)
          expect(tools).to eq([:functions])
        end
      end

      context "with unknown provider" do
        it "returns empty array" do
          tools = described_class.tools_for(:unknown_provider, :some_api)
          expect(tools).to eq([])
        end
      end

      context "with unknown API" do
        it "returns empty array" do
          tools = described_class.tools_for(:openai, :unknown_api)
          expect(tools).to eq([])
        end
      end

      context "with string arguments" do
        it "converts strings to symbols" do
          tools = described_class.tools_for("openai", "chat_completions")
          expect(tools).to eq([:functions])
        end
      end
    end

    describe ".supports_tools?" do
      it "returns true when API has tools" do
        expect(described_class.supports_tools?(:openai, :chat_completions)).to be true
        expect(described_class.supports_tools?(:openai, :responses)).to be true
        expect(described_class.supports_tools?(:openai, :assistants)).to be true
        expect(described_class.supports_tools?(:anthropic, :messages)).to be true
      end

      it "returns false when API has no tools" do
        expect(described_class.supports_tools?(:unknown, :api)).to be false
        expect(described_class.supports_tools?(:openai, :unknown)).to be false
      end
    end

    describe ".supports_feature?" do
      it "returns true for supported features" do
        expect(described_class.supports_feature?(:openai, :chat_completions, :streaming)).to be true
        expect(described_class.supports_feature?(:openai, :chat_completions, :vision)).to be true
        expect(described_class.supports_feature?(:openai, :responses, :conversation_state)).to be true
      end

      it "returns false for unsupported features" do
        expect(described_class.supports_feature?(:openai, :chat_completions, :conversation_state)).to be false
        expect(described_class.supports_feature?(:openai, :chat_completions, :threads)).to be false
      end

      it "returns false for unknown provider/API" do
        expect(described_class.supports_feature?(:unknown, :api, :streaming)).to be false
      end
    end

    describe ".features_for" do
      it "returns all features for an API" do
        features = described_class.features_for(:openai, :chat_completions)
        expect(features).to include(:streaming, :vision, :structured_output, :function_calling)
      end

      it "returns empty array for unknown provider/API" do
        features = described_class.features_for(:unknown, :api)
        expect(features).to eq([])
      end
    end

    describe "CAPABILITIES constant" do
      it "is frozen" do
        expect(described_class::CAPABILITIES).to be_frozen
      end

      it "has expected structure" do
        expect(described_class::CAPABILITIES).to be_a(Hash)
        expect(described_class::CAPABILITIES[:openai]).to be_a(Hash)
        expect(described_class::CAPABILITIES[:openai][:chat_completions]).to have_key(:tools)
        expect(described_class::CAPABILITIES[:openai][:chat_completions]).to have_key(:features)
      end
    end
  end
end
```

### 5.2 Updated Configuration Tests

**File:** `spec/lib/prompt_tracker/configuration_spec.rb`

Add these tests to the existing spec file:

```ruby
describe "#tools_for_api" do
  before do
    config.providers = {
      openai: {
        name: "OpenAI",
        apis: {
          chat_completions: { name: "Chat Completions" },
          responses: { name: "Responses" },
          assistants: { name: "Assistants" }
        }
      },
      anthropic: {
        name: "Anthropic",
        apis: {
          messages: { name: "Messages" }
        }
      }
    }
  end

  context "with OpenAI chat_completions" do
    it "returns functions tool with metadata" do
      tools = config.tools_for_api(:openai, :chat_completions)

      expect(tools.length).to eq(1)
      expect(tools.first[:id]).to eq("functions")
      expect(tools.first[:name]).to eq("Functions")
      expect(tools.first[:description]).to be_present
      expect(tools.first[:icon]).to eq("bi-braces-asterisk")
      expect(tools.first[:configurable]).to be true
    end
  end

  context "with OpenAI responses" do
    it "returns all tools with metadata" do
      tools = config.tools_for_api(:openai, :responses)

      expect(tools.length).to eq(4)
      tool_ids = tools.map { |t| t[:id] }
      expect(tool_ids).to contain_exactly("web_search", "file_search", "code_interpreter", "functions")

      # Verify each tool has required metadata
      tools.each do |tool|
        expect(tool[:name]).to be_present
        expect(tool[:description]).to be_present
        expect(tool[:icon]).to be_present
        expect(tool).to have_key(:configurable)
      end
    end
  end

  context "with OpenAI assistants" do
    it "returns builtin tools and functions" do
      tools = config.tools_for_api(:openai, :assistants)

      tool_ids = tools.map { |t| t[:id] }
      expect(tool_ids).to contain_exactly("code_interpreter", "file_search", "functions")
    end
  end

  context "with Anthropic messages" do
    it "returns functions tool" do
      tools = config.tools_for_api(:anthropic, :messages)

      expect(tools.length).to eq(1)
      expect(tools.first[:id]).to eq("functions")
    end
  end

  context "with unknown provider" do
    it "returns empty array" do
      tools = config.tools_for_api(:unknown, :api)
      expect(tools).to eq([])
    end
  end

  context "with unknown API" do
    it "returns empty array" do
      tools = config.tools_for_api(:openai, :unknown)
      expect(tools).to eq([])
    end
  end

  context "with string arguments" do
    it "converts to symbols" do
      tools = config.tools_for_api("openai", "chat_completions")
      expect(tools.length).to eq(1)
      expect(tools.first[:id]).to eq("functions")
    end
  end

  context "when tool metadata is missing" do
    before do
      # Remove a tool from builtin_tools
      config.builtin_tools.delete(:web_search)
    end

    it "skips tools without metadata" do
      tools = config.tools_for_api(:openai, :responses)
      tool_ids = tools.map { |t| t[:id] }

      # web_search should be skipped
      expect(tool_ids).not_to include("web_search")
      expect(tool_ids).to include("file_search", "code_interpreter", "functions")
    end
  end
end
```

### 5.3 Integration Test Scenarios

**File:** `spec/system/prompt_tracker/playground_tools_spec.rb` (new file)

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Playground Tools Integration", type: :system, js: true do
  let(:prompt) { create(:prompt_tracker_prompt) }
  let(:version) { create(:prompt_tracker_prompt_version, prompt: prompt) }

  before do
    # Configure OpenAI API key
    PromptTracker.configuration.api_keys = { openai: "sk-test-key" }
  end

  describe "Chat Completions API" do
    it "shows tools panel with functions only" do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, version)

      # Select Chat Completions API
      select "Chat Completions", from: "API"

      # Tools panel should be visible
      expect(page).to have_css('[data-playground-target="responseApiToolsContainer"]', visible: true)

      # Should show functions tool
      expect(page).to have_content("Functions")
      expect(page).to have_content("Define custom function schemas")

      # Should NOT show built-in tools
      expect(page).not_to have_content("Web Search")
      expect(page).not_to have_content("File Search")
      expect(page).not_to have_content("Code Interpreter")
    end
  end

  describe "Responses API" do
    it "shows tools panel with all tools" do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, version)

      # Select Responses API
      select "Responses", from: "API"

      # Tools panel should be visible
      expect(page).to have_css('[data-playground-target="responseApiToolsContainer"]', visible: true)

      # Should show all tools
      expect(page).to have_content("Web Search")
      expect(page).to have_content("File Search")
      expect(page).to have_content("Code Interpreter")
      expect(page).to have_content("Functions")
    end
  end

  describe "API switching" do
    it "updates tools panel when switching APIs" do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, version)

      # Start with Chat Completions
      select "Chat Completions", from: "API"
      expect(page).to have_content("Functions")
      expect(page).not_to have_content("Web Search")

      # Switch to Responses
      select "Responses", from: "API"
      expect(page).to have_content("Functions")
      expect(page).to have_content("Web Search")
      expect(page).to have_content("File Search")
      expect(page).to have_content("Code Interpreter")
    end
  end
end
```

### 5.4 Edge Cases and Error Handling Tests

**Additional test cases to add:**

```ruby
# In spec/lib/prompt_tracker/api_capabilities_spec.rb

describe "edge cases" do
  it "handles nil provider gracefully" do
    expect { described_class.tools_for(nil, :chat_completions) }.not_to raise_error
    expect(described_class.tools_for(nil, :chat_completions)).to eq([])
  end

  it "handles nil API gracefully" do
    expect { described_class.tools_for(:openai, nil) }.not_to raise_error
    expect(described_class.tools_for(:openai, nil)).to eq([])
  end

  it "handles empty string provider" do
    expect(described_class.tools_for("", :chat_completions)).to eq([])
  end

  it "handles empty string API" do
    expect(described_class.tools_for(:openai, "")).to eq([])
  end

  it "is case-sensitive for provider names" do
    # OpenAI vs openai
    expect(described_class.tools_for(:OpenAI, :chat_completions)).to eq([])
    expect(described_class.tools_for(:openai, :chat_completions)).to eq([:functions])
  end

  it "is case-sensitive for API names" do
    # Chat_Completions vs chat_completions
    expect(described_class.tools_for(:openai, :Chat_Completions)).to eq([])
    expect(described_class.tools_for(:openai, :chat_completions)).to eq([:functions])
  end
end
```

---

## 6. Acceptance Criteria

### 6.1 Functional Requirements

**Must Have:**
- [ ] `ApiCapabilities.tools_for(:openai, :chat_completions)` returns `[:functions]`
- [ ] `ApiCapabilities.tools_for(:openai, :responses)` returns `[:web_search, :file_search, :code_interpreter, :functions]`
- [ ] `ApiCapabilities.tools_for(:openai, :assistants)` returns `[:code_interpreter, :file_search, :functions]`
- [ ] `ApiCapabilities.tools_for(:anthropic, :messages)` returns `[:functions]`
- [ ] `Configuration#tools_for_api` delegates to `ApiCapabilities` and enriches with metadata
- [ ] Tools panel appears for Chat Completions API (currently hidden)
- [ ] Tools panel appears for Assistants API (currently hidden)
- [ ] Tools panel still appears for Responses API (no regression)
- [ ] Configuration panels render dynamically based on `configurable` flag
- [ ] Switching APIs updates the tools panel correctly

**Should Have:**
- [ ] All existing tests pass without modification
- [ ] New tests achieve >95% code coverage for `ApiCapabilities`
- [ ] No JavaScript console errors when using playground
- [ ] No performance degradation (tools load in <100ms)

**Nice to Have:**
- [ ] Helper method `provider_supports_tools?` uses `ApiCapabilities` directly (optimization)
- [ ] Documentation updated with new architecture diagrams
- [ ] CHANGELOG includes migration guide

### 6.2 Manual Testing Checklist

**Playground UI Testing:**
1. [ ] Open playground in browser
2. [ ] Select OpenAI → Chat Completions
   - [ ] Tools panel is visible
   - [ ] Only "Functions" tool appears
   - [ ] Checking "Functions" shows configuration panel
3. [ ] Select OpenAI → Responses
   - [ ] Tools panel is visible
   - [ ] All 4 tools appear (Web Search, File Search, Code Interpreter, Functions)
   - [ ] Checking "File Search" shows vector store configuration
   - [ ] Checking "Functions" shows function definition form
4. [ ] Select OpenAI → Assistants
   - [ ] Tools panel is visible
   - [ ] 3 tools appear (Code Interpreter, File Search, Functions)
   - [ ] "Web Search" does NOT appear
5. [ ] Switch between APIs multiple times
   - [ ] Tools panel updates correctly each time
   - [ ] No flickering or layout shifts
   - [ ] No JavaScript errors in console

**Data Persistence Testing:**
6. [ ] Configure tools in Chat Completions
7. [ ] Save prompt version
8. [ ] Reload page
   - [ ] Tool configuration is preserved
   - [ ] Configuration panels show correct data
9. [ ] Switch to different API and back
   - [ ] Tool configuration is still preserved

**Error Handling Testing:**
10. [ ] Remove OpenAI API key from initializer
11. [ ] Reload playground
    - [ ] No errors displayed
    - [ ] Tools panel gracefully hidden or shows appropriate message

### 6.3 Performance Considerations

**Benchmarks:**
- [ ] `ApiCapabilities.tools_for` executes in <1ms (simple hash lookup)
- [ ] `Configuration#tools_for_api` executes in <5ms (includes metadata mapping)
- [ ] Playground page load time unchanged (<2s)
- [ ] API switching response time <100ms

**Memory:**
- [ ] `CAPABILITIES` constant is frozen (no accidental mutations)
- [ ] No memory leaks when switching APIs repeatedly (test 100+ switches)

**Scalability:**
- [ ] Adding a new provider requires only updating `CAPABILITIES` hash
- [ ] Adding a new tool requires: symbol + partial + metadata (3 changes)
- [ ] No N+1 queries when loading tools

---

## 7. Future Considerations

### 7.1 How to Add New Providers/APIs

**Example: Adding Google Gemini support**

**Step 1:** Add to `ApiCapabilities::CAPABILITIES`

```ruby
CAPABILITIES = {
  # ... existing providers ...
  google: {
    gemini: {
      tools: [:functions, :code_execution],  # Gemini supports code execution
      features: [:streaming, :vision, :function_calling, :multimodal]
    }
  }
}.freeze
```

**Step 2:** Add tool metadata (if new tools introduced)

```ruby
# In Configuration#default_builtin_tools
def default_builtin_tools
  {
    # ... existing tools ...
    code_execution: {
      name: "Code Execution",
      description: "Execute code in a sandboxed environment",
      icon: "bi-terminal",
      configurable: false
    }
  }
end
```

**Step 3:** Create partial (if configurable)

```erb
<%# app/views/prompt_tracker/testing/playground/response_api_tools/_code_execution_configuration_panel.html.erb %>
<div id="code-execution-config" class="tool-config-panel">
  <!-- Configuration UI here -->
</div>
```

**That's it!** No changes to views, controllers, or JavaScript needed.

### 7.2 How to Add Model-Specific Restrictions (Future)

If a provider releases a model that doesn't support certain tools:

```ruby
module PromptTracker
  module ApiCapabilities
    # Model-specific restrictions (optional, for future use)
    MODEL_RESTRICTIONS = {
      openai: {
        chat_completions: {
          "gpt-3.5-turbo" => {
            excluded_tools: [:vision_tools]  # Example: older model doesn't support vision
          }
        }
      }
    }.freeze

    # Updated method with optional model parameter
    def self.tools_for(provider, api, model: nil)
      base_tools = CAPABILITIES.dig(provider.to_sym, api.to_sym, :tools) || []

      # If model-specific restrictions exist, filter tools
      if model && MODEL_RESTRICTIONS.dig(provider.to_sym, api.to_sym, model)
        excluded = MODEL_RESTRICTIONS.dig(provider.to_sym, api.to_sym, model, :excluded_tools) || []
        base_tools - excluded
      else
        base_tools
      end
    end
  end
end
```

**Backward compatible:** The `model:` parameter is optional, so existing code continues to work.

### 7.3 Extensibility Points

**1. Custom Tool Types**

Users can add custom tools by:
- Adding to their initializer's `builtin_tools` hash
- Creating a partial following the naming convention
- Tools will automatically appear if added to `ApiCapabilities::CAPABILITIES`

**2. Provider-Specific Tool Behavior**

If a tool behaves differently across providers:

```ruby
# In the partial
<% if current_provider == :openai %>
  <!-- OpenAI-specific configuration -->
<% elsif current_provider == :anthropic %>
  <!-- Anthropic-specific configuration -->
<% end %>
```

**3. Dynamic Tool Discovery**

Future enhancement: Query provider APIs to discover available tools dynamically:

```ruby
def self.tools_for(provider, api, dynamic: false)
  if dynamic
    # Query provider API for available tools
    discover_tools_from_api(provider, api)
  else
    # Use static capability matrix
    CAPABILITIES.dig(provider.to_sym, api.to_sym, :tools) || []
  end
end
```

### 7.4 Migration Path for Breaking Changes

**If we need to change the capability matrix structure:**

1. Add new structure alongside old one
2. Deprecate old structure with warnings
3. Provide migration script
4. Remove old structure in next major version

**Example:**

```ruby
# Version 1.x (current)
CAPABILITIES = {
  openai: {
    chat_completions: {
      tools: [:functions]
    }
  }
}

# Version 2.x (future - more detailed)
CAPABILITIES_V2 = {
  openai: {
    chat_completions: {
      tools: {
        functions: {
          max_count: 128,
          supports_parallel: true,
          supports_strict_mode: true
        }
      }
    }
  }
}

# Adapter for backward compatibility
def self.tools_for(provider, api)
  if CAPABILITIES_V2.dig(provider, api, :tools)
    CAPABILITIES_V2.dig(provider, api, :tools).keys
  else
    CAPABILITIES.dig(provider, api, :tools) || []
  end
end
```

---

## 8. Rollback Plan

If issues are discovered after deployment:

**Phase 1 Rollback (ApiCapabilities service only):**
- Remove `lib/prompt_tracker/api_capabilities.rb`
- Remove `spec/lib/prompt_tracker/api_capabilities_spec.rb`
- No impact on users (service not yet used)

**Phase 2 Rollback (Configuration changes):**
- Revert `Configuration#tools_for_api` to read from initializer `capabilities`
- Revert Configuration spec changes
- Users must keep `capabilities` in initializer

**Phase 3 Rollback (View changes):**
- Revert `_response_api_tools.html.erb` to hardcoded partial renders
- No data loss (tool configurations stored in database unchanged)

**Phase 4 Rollback (Initializer cleanup):**
- Add `capabilities` back to initializer API configs
- Update migration guide to reverse the changes

**Full Rollback:**
- Revert all commits in reverse order (Phase 5 → Phase 1)
- Run `git revert <commit-range>`
- Deploy reverted code
- Notify users to restore `capabilities` in initializers

---

## 9. Success Metrics

**Quantitative:**
- [ ] 0 regressions in existing functionality
- [ ] 100% of new code covered by tests
- [ ] <5ms performance overhead for `tools_for_api` calls
- [ ] 0 JavaScript console errors in playground

**Qualitative:**
- [ ] Tools panel appears for all APIs that support tools
- [ ] Adding a new tool requires ≤3 file changes
- [ ] Code is easier to understand (reduced cognitive load)
- [ ] Documentation is clear and complete

**User Impact:**
- [ ] Users can now use functions with Chat Completions API
- [ ] Users can now use tools with Assistants API
- [ ] No user action required (except removing `capabilities` from initializer)

---

## 10. Appendix

### 10.1 Related Documentation

- OpenAI Chat Completions API: `docs/llm_providers/openai/chat_completions.md`
- OpenAI Responses API: `docs/llm_providers/openai/responses_api.md`
- OpenAI Assistants API: `docs/llm_providers/openai/assistants_api.md`
- Anthropic Messages API: `docs/llm_providers/anthropic/messages_api.md`

### 10.2 Glossary

- **API Capability:** A feature that an API supports (e.g., tools, streaming, vision)
- **Tool:** A function or built-in feature that the LLM can use (e.g., web_search, functions)
- **Built-in Tool:** A tool provided by the LLM provider (e.g., web_search, code_interpreter)
- **Custom Function:** A developer-defined function schema that the LLM can call
- **Configurable Tool:** A tool that requires user configuration (e.g., file_search needs vector stores)
- **Convention-based Rendering:** Automatically rendering partials based on naming conventions

### 10.3 Open Questions

1. **Should we support tool aliases?** (e.g., `code_execution` vs `code_interpreter`)
   - **Decision:** No, keep tool IDs consistent with provider documentation

2. **Should we validate tool configurations?** (e.g., ensure vector_store_ids are valid)
   - **Decision:** Defer to Phase 6 (validation layer)

3. **Should we cache `tools_for_api` results?**
   - **Decision:** No, hash lookup is fast enough (<1ms)

4. **Should we support tool versioning?** (e.g., `web_search_v2`)
   - **Decision:** Not needed yet, revisit if providers version their tools

---

**End of Document**
