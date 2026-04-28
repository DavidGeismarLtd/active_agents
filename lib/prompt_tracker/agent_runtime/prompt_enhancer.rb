# frozen_string_literal: true

module PromptTracker
  module AgentRuntime
    # Appends planning and iteration-budget instructions to a base system prompt.
    # Pure Ruby — no Rails dependencies.
    module PromptEnhancer
      module_function

      # @param original_prompt [String] the base system prompt
      # @param phase [Symbol] :planning or :execution
      def with_planning(original_prompt, phase: :execution)
        base = original_prompt.to_s
        base + (phase == :planning ? planning_phase_instructions : execution_phase_instructions)
      end

      # @param system_prompt [String]
      # @param iteration [Integer] 1-based current iteration
      # @param max_iterations [Integer]
      def with_iteration_context(system_prompt, iteration:, max_iterations:)
        return system_prompt unless max_iterations && iteration > 0

        remaining = max_iterations - iteration
        suffix = if iteration >= max_iterations
          final_iteration_instructions(iteration, max_iterations)
        elsif remaining == 1
          penultimate_iteration_instructions(iteration, max_iterations)
        else
          standard_iteration_instructions(iteration, max_iterations, remaining)
        end

        system_prompt.to_s + suffix
      end

      def planning_phase_instructions
        <<~INSTRUCTIONS


          ## 🎯 PLANNING PHASE

          This is the PLANNING PHASE. Your ONLY job right now is to create a plan.

          **What to do:**
          1. Understand the task goal from the user's request
          2. Call `create_plan(goal, steps)` with:
             - A clear, specific goal statement
             - 3-7 concrete, actionable steps
          3. Do NOT execute any work yet - just create the plan

          **Important:**
          - Steps should be ACTUAL WORK steps (e.g., "Fetch news articles", "Analyze data", "Generate summary")
          - Do NOT include "Create a plan" as a step - that's what you're doing right now
          - Each step should be specific and measurable
          - Steps should be in logical order

          Now, create your plan!
        INSTRUCTIONS
      end

      def execution_phase_instructions
        <<~INSTRUCTIONS


          ## 🎯 EXECUTION PHASE

          You have already created a plan. Now execute it step by step.

          **Workflow:**

          1. **Check Your Plan**: Call `get_plan()` to see your current plan and step statuses
          2. **Execute Steps Sequentially**:
             - Work on ONE step at a time
             - Before starting: `update_step(step_id, "in_progress", "Starting...")`
             - After success: `update_step(step_id, "completed", "Summary of results")`
             - After failure: `update_step(step_id, "failed", "Error: [description]")`
          3. **Handle Errors Gracefully**: Mark failing steps as "failed" and decide whether to continue or abort
          4. **Adapt if Needed**: `add_step()` for new work, `update_step(..., "skipped", ...)` for work that's no longer needed
          5. **Clean Up Before Completion** (CRITICAL):
             - Before calling `mark_task_complete()`, ALL steps must be in a terminal state
             - Any "in_progress" → complete/fail/skip them
             - Any "pending" that won't be done → skip them
          6. **Complete Explicitly**: Call `mark_task_complete(summary)` when done — even if you hit errors
          7. **Never Over-Iterate**: Don't perform redundant work. Trust your initial findings.

          REMEMBER: The UI shows step statuses to users. Always keep them accurate.
        INSTRUCTIONS
      end

      def standard_iteration_instructions(iteration, max_iterations, remaining)
        <<~INSTRUCTIONS

          ## ⏱️ ITERATION STATUS
          You are on iteration #{iteration} of #{max_iterations}.
          You have #{remaining} iterations remaining.
          Pace yourself accordingly — prioritize the most important work first.
        INSTRUCTIONS
      end

      def penultimate_iteration_instructions(iteration, max_iterations)
        <<~INSTRUCTIONS

          ## ⚠️ ITERATION STATUS — ALMOST OUT OF TIME
          You are on iteration #{iteration} of #{max_iterations}.
          You have only 1 iteration remaining after this one.
          Start wrapping up:
          - Finish the current step if possible
          - On your next (final) iteration you MUST produce a summary and complete the task
          - Do NOT start any new major work
        INSTRUCTIONS
      end

      def final_iteration_instructions(iteration, max_iterations)
        <<~INSTRUCTIONS

          ## 🛑 FINAL ITERATION — YOU MUST WRAP UP NOW
          You are on iteration #{iteration} of #{max_iterations}. This is your LAST iteration.
          You will NOT get another turn after this.

          **You MUST do the following:**
          1. Do NOT start any new work or function calls
          2. Summarize what you have accomplished so far
          3. Note any work that remains incomplete
          4. Call `mark_task_complete()` with a summary of completed and incomplete work
          5. If mark_task_complete is not available, simply produce a final summary as your response

          Failure to wrap up will result in the task being forcibly terminated with no summary.
        INSTRUCTIONS
      end
    end
  end
end
