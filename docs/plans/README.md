# PromptTracker Planning Documents

This directory contains detailed planning documents for major features and architectural decisions.

## 📚 Current Plans

### Assistant Conversation Testing (UPDATED)

A comprehensive feature to test OpenAI Assistants through LLM-simulated conversations with per-message scoring.

**⭐ START HERE: [Implementation Summary](./IMPLEMENTATION_SUMMARY.md)**

**Documents (Read in order):**
1. **[Implementation Summary](./IMPLEMENTATION_SUMMARY.md)** ⭐ **START HERE** - High-level overview of changes and updated timeline
2. **[Quick Start Guide](./assistant-testing-quickstart.md)** - TL;DR overview and core concepts (updated)
3. **[MVP Plan](./assistant-conversation-testing-mvp.md)** - Complete implementation plan with 8 phases and comprehensive testing strategy
4. **[Architecture Diagrams](./assistant-testing-architecture.md)** - Visual diagrams of system architecture and data flow
5. **[Key Decisions](./assistant-testing-decisions.md)** - Architectural decisions with NEW DECISIONS section (0.1-0.7)
6. **[Implementation Checklist (UPDATED)](./assistant-testing-checklist-updated.md)** ⭐ **USE THIS** - Detailed task list with all new requirements
7. **[Usage Examples](./assistant-testing-examples.md)** - Real-world examples and code samples
8. **[Original Checklist](./assistant-testing-checklist.md)** - Original plan (reference only)

**Quick Summary:**
- **Goal:** Test assistants with realistic, LLM-simulated conversations
- **Approach:** Polymorphic testable (PromptVersion OR Assistant)
- **Key Innovations:**
  - User simulator LLM generates natural conversation turns
  - **Per-message scoring** (judge scores each assistant message individually)
  - **Unified testable index** (all testables in one view)
  - **Creation wizard** (guided testable creation)
  - **Auto-fetch from OpenAI API** (always up-to-date)
- **Evaluation:** LLM judge scores each assistant message (0-100) with reasons, overall score = average
- **Timeline:** 23-31 hours (~4-5 days) - UPDATED

**New to this feature?** Read the [Implementation Summary](./IMPLEMENTATION_SUMMARY.md) first!

---

## 🗂️ Document Structure

### Planning Documents Should Include:

1. **Vision & Goals**
   - What problem are we solving?
   - What's the desired outcome?

2. **Architecture Overview**
   - High-level design
   - Key components
   - Data flow

3. **Detailed Specifications**
   - Database schema
   - Model definitions
   - Service interfaces
   - API contracts

4. **Implementation Plan**
   - Phases with time estimates
   - Dependencies
   - Risks and mitigations

5. **Success Criteria**
   - How do we know it's done?
   - What metrics matter?

6. **Examples & Usage**
   - Code samples
   - Common use cases
   - Integration patterns

---

## 📋 Template for New Plans

When creating a new planning document, use this structure:

```markdown
# Feature Name - Plan

## 🎯 Vision
[What are we building and why?]

## 📋 Scope
### In Scope ✅
### Out of Scope ❌

## 🏗️ Architecture
[High-level design]

## 📊 Database Schema
[Tables, columns, indexes]

## 🔧 Implementation Plan
### Phase 1: [Name]
### Phase 2: [Name]
...

## 📝 Detailed Specifications
[Code examples, interfaces]

## 🎯 Success Criteria
[Definition of done]

## 📈 Timeline
[Estimates]

## 📚 Examples
[Usage examples]
```

---

## 🚀 How to Use These Plans

### For Developers:
1. Read the MVP plan to understand the feature
2. Review key decisions to understand trade-offs
3. Follow the implementation checklist
4. Reference examples for usage patterns

### For Product Managers:
1. Read the vision and scope sections
2. Review success criteria
3. Check timeline estimates
4. Validate against user needs

### For Reviewers:
1. Check architectural decisions
2. Verify scope is appropriate
3. Validate technical approach
4. Ensure examples are clear

---

## 📝 Contributing

When adding new planning documents:

1. **Create a feature branch**
   ```bash
   git checkout -b plan/feature-name
   ```

2. **Add your documents**
   - Main plan: `feature-name-mvp.md`
   - Decisions: `feature-name-decisions.md`
   - Checklist: `feature-name-checklist.md`
   - Examples: `feature-name-examples.md`

3. **Update this README**
   - Add to "Current Plans" section
   - Include quick summary

4. **Create PR for review**
   - Tag relevant stakeholders
   - Include context in PR description

---

## 🗄️ Archive

Completed or deprecated plans are moved to `archive/` directory.

---

## 📞 Questions?

If you have questions about any planning document:
- Open a GitHub issue with `[Planning]` prefix
- Tag the document author
- Reference specific sections

---

**Last Updated:** 2025-12-20
