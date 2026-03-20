# Monaco Editor Integration

## Overview

PromptTracker uses **Monaco Editor** (the same editor that powers VS Code) for code editing in the Function Library. This provides a professional development experience with syntax highlighting, autocomplete, error detection, and more.

## Features

### ✨ Syntax Highlighting
- **Ruby**: Full syntax highlighting for function code
- **JSON**: Syntax highlighting for parameters, environment variables, dependencies, and examples
- Automatic error detection and inline warnings

### 🎨 Editor Features
- **Line numbers** - Easy navigation
- **Minimap** - Quick overview of code structure (for Ruby code)
- **Auto-formatting** - Format on paste and type
- **Word wrap** - No horizontal scrolling
- **Tab support** - 2-space indentation
- **Automatic layout** - Resizes with window

### 📝 Code Templates
Pre-built templates for common function patterns:
- **Basic Function** - Simple template with argument handling
- **API Call** - Make HTTP requests to external APIs
- **Data Processing** - Process and transform data
- **Validation** - Validate input data
- **Conditional Logic** - Execute different logic based on conditions

## Usage

### In the Function Form

Monaco Editor is automatically initialized for the following fields:

1. **Function Code** (Ruby)
   - Height: 500px
   - Minimap: Enabled
   - Language: Ruby
   - Template button available

2. **Parameters** (JSON)
   - Height: 300px
   - Minimap: Disabled
   - Language: JSON

3. **Environment Variables** (JSON)
   - Height: 200px
   - Minimap: Disabled
   - Language: JSON

4. **Dependencies** (JSON)
   - Height: 150px
   - Minimap: Disabled
   - Language: JSON

5. **Example Input/Output** (JSON)
   - Height: 200px
   - Minimap: Disabled
   - Language: JSON

### Using Code Templates

1. Click the **"Use Template"** button in the Function Code section
2. Select a template from the modal
3. The template code will be inserted into the editor
4. Customize the code for your needs

## Technical Details

### Loading Monaco

Monaco Editor is loaded from CDN:
```
https://cdn.jsdelivr.net/npm/monaco-editor@0.45.0/min/vs/loader.js
```

The editor is lazy-loaded only when needed (when the form is displayed).

### Stimulus Controller

The `monaco-editor` Stimulus controller manages editor instances:

**Targets:**
- `container` - The div where Monaco is mounted
- `textarea` - The hidden textarea that syncs with the editor

**Values:**
- `language` - Programming language (ruby, json)
- `theme` - Editor theme (vs, vs-dark)
- `readOnly` - Whether editor is read-only
- `minimap` - Whether to show minimap
- `lineNumbers` - Whether to show line numbers
- `height` - Editor height (e.g., "500px")

**Example:**
```erb
<div data-controller="monaco-editor"
     data-monaco-editor-language-value="ruby"
     data-monaco-editor-height-value="500px"
     data-monaco-editor-minimap-value="true">
  <div data-monaco-editor-target="container"></div>
  <%= f.text_area :code, data: { monaco_editor_target: "textarea" } %>
</div>
```

### Theme Support

Monaco Editor automatically adapts to the page theme:
- **Light theme**: Uses `vs` theme
- **Dark theme**: Uses `vs-dark` theme

The theme updates when the user toggles the page theme.

### Form Submission

The editor content is automatically synced to the hidden textarea on every change, so form submission works seamlessly without any special handling.

## Configuration

### Customizing Editor Options

To customize editor options, modify the `monaco-editor` controller:

```javascript
// app/javascript/prompt_tracker/controllers/monaco_editor_controller.js

this.editor = window.monaco.editor.create(this.containerTarget, {
  // Add or modify options here
  fontSize: 14,
  tabSize: 2,
  wordWrap: "on",
  // ... other options
})
```

### Adding New Languages

To add support for new languages:

1. Set the `language` value in the view:
   ```erb
   data-monaco-editor-language-value="python"
   ```

2. Monaco automatically supports: JavaScript, TypeScript, Python, Go, Rust, and many more.

## Browser Compatibility

Monaco Editor supports:
- Chrome/Edge (latest)
- Firefox (latest)
- Safari (latest)

**Note**: Monaco requires a modern browser with ES6 support.

## Performance

- **Lazy loading**: Monaco is only loaded when the function form is displayed
- **Single instance**: Monaco loader is loaded once and reused
- **Automatic cleanup**: Editors are disposed when the controller disconnects

## Troubleshooting

### Editor not loading

1. Check browser console for errors
2. Verify CDN is accessible
3. Check that Stimulus controller is registered

### Content not saving

1. Verify the textarea has the correct `data-monaco-editor-target="textarea"` attribute
2. Check that the editor is syncing on change events
3. Inspect the form data before submission

### Theme not updating

1. Verify the page theme is set correctly
2. Check that the `updateTheme()` method is being called
3. Ensure Monaco is fully loaded before theme change

## Future Enhancements

Potential improvements:
- [ ] IntelliSense for Ruby standard library
- [ ] Custom snippets for common patterns
- [ ] Diff editor for comparing function versions
- [ ] Collaborative editing (multiple users)
- [ ] Vim/Emacs keybindings
- [ ] Code folding for large functions

