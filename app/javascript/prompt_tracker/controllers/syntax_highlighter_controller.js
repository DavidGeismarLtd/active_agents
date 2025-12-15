import { Controller } from "@hotwired/stimulus"

/**
 * SyntaxHighlighter Stimulus Controller
 * Provides syntax highlighting for prompt editors
 * Highlights: variables {{ var }}, sections #role, Liquid tags {% %}, filters |
 */
export default class extends Controller {
  static targets = ["textarea", "highlight"]

  connect() {
    this.updateHighlight()
  }

  // Called when textarea content changes
  onInput() {
    this.updateHighlight()
  }

  updateHighlight() {
    if (!this.hasTextareaTarget || !this.hasHighlightTarget) return

    const text = this.textareaTarget.value
    const highlighted = this.highlightSyntax(text)
    this.highlightTarget.innerHTML = highlighted
  }

  highlightSyntax(text) {
    if (!text) return ''

    // Escape HTML first
    let result = this.escapeHtml(text)

    // Highlight in order of precedence:
    // 1. Sections: #role, #goal, #context, etc. (at start of line)
    result = this.highlightSections(result)

    // 2. Liquid tags: {% if %}, {% for %}, {% endif %}, etc.
    result = this.highlightLiquidTags(result)

    // 3. Variables with filters: {{ name | capitalize }}
    result = this.highlightVariablesWithFilters(result)

    // 4. Simple variables: {{ name }}
    result = this.highlightVariables(result)

    return result
  }

  highlightSections(text) {
    // Match sections at the start of a line: #role, #goal, #context, etc.
    // Known sections from the UI spec
    const sections = [
      'role', 'goal', 'context', 'format', 'example', 'audience',
      'step by step instructions', 'reasoning approach', 'tone & style',
      'tone and style', 'what to prioritise', 'what to prioritize',
      'out of scope', 'resources'
    ]

    const sectionPattern = new RegExp(
      `(^|\\n)(#(?:${sections.join('|')}))(?=\\s|:|$)`,
      'gim'
    )

    return text.replace(sectionPattern, (match, lineStart, section) => {
      return `${lineStart}<span class="highlight-section">${section}</span>`
    })
  }

  highlightLiquidTags(text) {
    // Match {% ... %}
    return text.replace(/(\{%[^%]*%\})/g, '<span class="highlight-liquid-tag">$1</span>')
  }

  highlightVariablesWithFilters(text) {
    // Match {{ variable | filter }} or {{ variable | filter1 | filter2 }}
    return text.replace(/(\{\{[^}]*\|[^}]*\}\})/g, (match) => {
      // Split into variable and filter parts
      const parts = match.split('|')
      const variable = parts[0] // {{ variable
      const filters = parts.slice(1).join('|') // filter }} or filter1 | filter2 }}

      return `<span class="highlight-variable">${variable}</span><span class="highlight-liquid-filter">|${filters}</span>`
    })
  }

  highlightVariables(text) {
    // Match {{ variable }} (without filters, already handled above)
    return text.replace(/(\{\{[^}|]*\}\})/g, '<span class="highlight-variable">$1</span>')
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
