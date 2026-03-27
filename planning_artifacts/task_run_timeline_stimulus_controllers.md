# Task Run Timeline - Stimulus Controller Reusability Analysis

## 📊 Summary

**Total existing controllers:** 40+
**Reusable for timeline:** 2 controllers ✅
**New controllers needed:** 1 controller 🆕

---

## ✅ Reusable Controllers

### 1. `prompt_search_controller.js` → Timeline Search

**Current Location:** `app/javascript/prompt_tracker/controllers/prompt_search_controller.js`

**Current Functionality:**
- Searches prompts by name
- Filters version rows
- Auto-expands accordion items with matches
- Shows/hides items based on query

**How to Reuse:**
```erb
<!-- In task_runs/show.html.erb -->
<div data-controller="prompt-search">
  <input type="text" 
         placeholder="Search timeline..." 
         data-action="input->prompt-search#search"
         class="form-control">
  
  <!-- Timeline events -->
  <div data-prompt-search-target="item" 
       data-searchable-content="<%= event_searchable_text(event) %>">
    <!-- Event card content -->
  </div>
</div>
```

**Adaptations Needed:**
- Change `data-prompt-name` to `data-searchable-content`
- Helper method to extract searchable text from events (prompts, responses, arguments, results)
- Search within nested JSON content

**Benefits:**
- ✅ Already handles auto-expand logic
- ✅ Already handles show/hide based on query
- ✅ Already normalizes query (lowercase, trim)
- ✅ No localStorage needed (search is ephemeral)

---

### 2. `column_visibility_controller.js` → Event Type Filtering

**Current Location:** `app/javascript/prompt_tracker/controllers/column_visibility_controller.js`

**Current Functionality:**
- Show/hide table columns via checkboxes
- Persist preferences in localStorage
- Show all / Hide all buttons

**How to Adapt:**
```javascript
// Rename to: timeline_event_filter_controller.js
// Change data attributes:
// - data-column → data-event-type
// - data-column-name → data-event-type-name

// Event types:
// - "llm_call"
// - "function_execution"
// - "planning_event"
// - "tool_intent"
// - "decision_marker"
```

**Usage:**
```erb
<!-- Filter controls -->
<div data-controller="timeline-event-filter" 
     data-timeline-event-filter-storage-key-value="taskTimelineFilters">
  
  <label>
    <input type="checkbox" 
           data-timeline-event-filter-target="checkbox"
           data-event-type-name="llm_call"
           data-action="change->timeline-event-filter#toggle"
           checked>
    LLM Calls
  </label>
  
  <!-- Timeline events -->
  <div data-event-type="llm_call">
    <!-- LLM call card -->
  </div>
</div>
```

**Adaptations Needed:**
- Rename controller file
- Change `data-column` to `data-event-type` in methods
- Update localStorage key to be timeline-specific

**Benefits:**
- ✅ Already handles localStorage persistence
- ✅ Already has show/hide all functionality
- ✅ Already manages checkbox state
- ✅ Minimal changes needed

---

## 🆕 New Controller Needed

### `task_timeline_controller.js` - Expand/Collapse & Copy

**Responsibilities:**
1. Expand/collapse iteration groups
2. Expand/collapse individual event cards
3. Expand all / Collapse all buttons
4. Copy to clipboard (individual events, iterations, full timeline)
5. Optional: Persist expand/collapse state in localStorage

**Implementation:**
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "iterationGroup",    // All iteration containers
    "eventCard",         // All expandable event cards
    "expandAllButton",   // Expand all button
    "collapseAllButton"  // Collapse all button
  ]
  
  static values = {
    storageKey: { type: String, default: "taskTimelineState" }
  }
  
  connect() {
    // Optional: Load saved state from localStorage
    this.loadState()
  }
  
  expandAll() {
    this.iterationGroupTargets.forEach(group => this.expand(group))
    this.eventCardTargets.forEach(card => this.expand(card))
    this.saveState()
  }
  
  collapseAll() {
    this.iterationGroupTargets.forEach(group => this.collapse(group))
    this.eventCardTargets.forEach(card => this.collapse(card))
    this.saveState()
  }
  
  toggleIteration(event) {
    const group = event.currentTarget.closest('[data-task-timeline-target="iterationGroup"]')
    this.toggle(group)
    this.saveState()
  }
  
  toggleCard(event) {
    const card = event.currentTarget.closest('[data-task-timeline-target="eventCard"]')
    this.toggle(card)
    this.saveState()
  }
  
  copyEvent(event) {
    const eventData = JSON.parse(event.currentTarget.dataset.eventJson)
    this.copyToClipboard(JSON.stringify(eventData, null, 2))
    this.showToast("Event copied!")
  }
  
  copyIteration(event) {
    const iterationData = JSON.parse(event.currentTarget.dataset.iterationJson)
    this.copyToClipboard(JSON.stringify(iterationData, null, 2))
    this.showToast("Iteration copied!")
  }
  
  copyTimeline() {
    const timelineData = this.element.dataset.timelineJson
    this.copyToClipboard(timelineData)
    this.showToast("Timeline copied!")
  }
  
  // Helper methods
  toggle(element) { /* ... */ }
  expand(element) { /* ... */ }
  collapse(element) { /* ... */ }
  copyToClipboard(text) { /* ... */ }
  showToast(message) { /* ... */ }
  saveState() { /* ... */ }
  loadState() { /* ... */ }
}
```

---

## 📋 Implementation Checklist

### Phase 1: Reuse Existing Controllers
- [ ] Copy `prompt_search_controller.js` logic (no changes needed to controller)
- [ ] Create helper method `event_searchable_text(event)` in `TaskRunsHelper`
- [ ] Add `data-controller="prompt-search"` to timeline container
- [ ] Add `data-searchable-content` to each event

### Phase 2: Adapt Column Visibility Controller
- [ ] Copy `column_visibility_controller.js` to `timeline_event_filter_controller.js`
- [ ] Replace `column` with `event-type` in all methods
- [ ] Update localStorage key to `taskTimelineFilters`
- [ ] Add filter checkboxes to timeline toolbar
- [ ] Add `data-event-type` to each event card

### Phase 3: Create New Timeline Controller
- [ ] Create `task_timeline_controller.js`
- [ ] Implement expand/collapse logic
- [ ] Implement copy to clipboard
- [ ] Add expand/collapse buttons to toolbar
- [ ] Add copy buttons to cards
- [ ] Optional: Add state persistence

---

## 🎯 Benefits of Reusing Controllers

1. **Less Code to Write:** ~150 lines saved by reusing search + filter controllers
2. **Proven Patterns:** These controllers are already tested and working
3. **Consistent UX:** Users familiar with search/filter patterns elsewhere in the app
4. **Faster Development:** Focus on new functionality (expand/collapse, copy)
5. **Maintainability:** Fewer controllers to maintain long-term

