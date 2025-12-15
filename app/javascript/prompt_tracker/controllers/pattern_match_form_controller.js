import { Controller } from "@hotwired/stimulus"

/**
 * Pattern Match Form Stimulus Controller
 * Provides UI/UX enhancements for regex pattern input:
 * - Live pattern validation
 * - Pattern count indicator
 * - Quick pattern insertion
 * - Visual feedback for valid/invalid patterns
 */
export default class extends Controller {
  static targets = ["patternsInput", "patternCount", "validationFeedback"]

  connect() {
    // Initial validation on load
    this.validatePatterns()
  }

  /**
   * Insert a common pattern at cursor position or end of text
   */
  insertPattern(event) {
    const pattern = event.currentTarget.dataset.pattern
    const textarea = this.patternsInputTarget
    const cursorPos = textarea.selectionStart
    const textBefore = textarea.value.substring(0, cursorPos)
    const textAfter = textarea.value.substring(cursorPos)
    
    // Add newline if not at start and previous line doesn't end with newline
    const prefix = (textBefore.length > 0 && !textBefore.endsWith('\n')) ? '\n' : ''
    
    // Insert pattern
    textarea.value = textBefore + prefix + pattern + '\n' + textAfter
    
    // Move cursor to end of inserted pattern
    const newCursorPos = cursorPos + prefix.length + pattern.length + 1
    textarea.setSelectionRange(newCursorPos, newCursorPos)
    textarea.focus()
    
    // Trigger validation
    this.validatePatterns()
  }

  /**
   * Validate patterns and provide visual feedback
   */
  validatePatterns() {
    const textarea = this.patternsInputTarget
    const patterns = this.getPatterns()
    
    // Update pattern count
    this.updatePatternCount(patterns.length)
    
    // Validate each pattern
    const validationResults = patterns.map((pattern, index) => {
      return this.validatePattern(pattern, index + 1)
    })
    
    // Display validation feedback
    this.displayValidationFeedback(validationResults)
  }

  /**
   * Get array of non-empty patterns from textarea
   */
  getPatterns() {
    const text = this.patternsInputTarget.value
    return text
      .split('\n')
      .map(line => line.trim())
      .filter(line => line.length > 0)
  }

  /**
   * Update pattern count badge
   */
  updatePatternCount(count) {
    if (this.hasPatternCountTarget) {
      const plural = count === 1 ? 'pattern' : 'patterns'
      this.patternCountTarget.textContent = `${count} ${plural}`
      
      // Update badge color based on count
      this.patternCountTarget.className = 'badge ' + (count > 0 ? 'bg-success' : 'bg-secondary')
    }
  }

  /**
   * Validate a single pattern
   */
  validatePattern(pattern, lineNumber) {
    // Check if pattern is in /pattern/flags format
    const regexMatch = pattern.match(/^\/(.+?)\/([gimsuvy]*)$/)
    
    if (!regexMatch) {
      return {
        line: lineNumber,
        pattern: pattern,
        valid: false,
        error: 'Pattern must be in /pattern/ or /pattern/flags format'
      }
    }
    
    const [, patternBody, flags] = regexMatch
    
    // Try to create a RegExp to validate syntax
    try {
      new RegExp(patternBody, flags)
      return {
        line: lineNumber,
        pattern: pattern,
        valid: true
      }
    } catch (e) {
      return {
        line: lineNumber,
        pattern: pattern,
        valid: false,
        error: e.message
      }
    }
  }

  /**
   * Display validation feedback
   */
  displayValidationFeedback(results) {
    if (!this.hasValidationFeedbackTarget) return
    
    const invalidPatterns = results.filter(r => !r.valid)
    
    if (invalidPatterns.length === 0 && results.length > 0) {
      // All patterns valid
      this.validationFeedbackTarget.innerHTML = `
        <div class="alert alert-success py-2 mb-0">
          <i class="bi bi-check-circle"></i> All patterns are valid!
        </div>
      `
    } else if (invalidPatterns.length > 0) {
      // Show errors
      const errorList = invalidPatterns.map(r => `
        <li><strong>Line ${r.line}:</strong> ${this.escapeHtml(r.error)}</li>
      `).join('')
      
      this.validationFeedbackTarget.innerHTML = `
        <div class="alert alert-warning py-2 mb-0">
          <i class="bi bi-exclamation-triangle"></i> <strong>Pattern errors:</strong>
          <ul class="mb-0 mt-1 small">
            ${errorList}
          </ul>
        </div>
      `
    } else {
      // No patterns
      this.validationFeedbackTarget.innerHTML = ''
    }
  }

  /**
   * Escape HTML to prevent XSS
   */
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}

