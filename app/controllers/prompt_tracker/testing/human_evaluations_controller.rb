# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for managing human evaluations in testing context
    class HumanEvaluationsController < ApplicationController
      before_action :set_prompt_test_run, only: [ :create ]

      # POST /testing/runs/:run_id/human_evaluations
      # Create a new human evaluation for a test run
      def create
        @human_evaluation = @prompt_test_run.human_evaluations.build(human_evaluation_params)

        if @human_evaluation.save
          respond_to do |format|
            format.turbo_stream do
              # Close the modal properly using custom Turbo Stream action
              # This ensures Bootstrap's modal lifecycle is respected and backdrop is cleaned up
              # The HumanEvaluation after_create_commit callback will broadcast the row update
              render turbo_stream: [
                turbo_stream.action(:close_modal, "human-evaluation-modal-#{@prompt_test_run.id}"),
                turbo_stream.append("flash-messages", partial: "prompt_tracker/shared/flash",
                                    locals: { type: "notice", message: "Human evaluation added successfully! Score: #{@human_evaluation.score}" })
              ]
            end
            format.html do
              redirect_to testing_prompt_prompt_version_prompt_test_path(
                            @prompt_test_run.prompt_version.prompt,
                            @prompt_test_run.prompt_version,
                            @prompt_test_run.prompt_test
                          ),
                          notice: "Human evaluation added successfully! Score: #{@human_evaluation.score}"
            end
          end
        else
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.append("flash-messages", partial: "prompt_tracker/shared/flash",
                                                        locals: { type: "alert", message: "Error: #{@human_evaluation.errors.full_messages.join(', ')}" })
            end
            format.html do
              redirect_to testing_prompt_prompt_version_prompt_test_path(
                            @prompt_test_run.prompt_version.prompt,
                            @prompt_test_run.prompt_version,
                            @prompt_test_run.prompt_test
                          ),
                          alert: "Error creating human evaluation: #{@human_evaluation.errors.full_messages.join(', ')}"
            end
          end
        end
      end

      private

      def set_prompt_test_run
        @prompt_test_run = TestRun.find(params[:run_id])
      end

      def human_evaluation_params
        params.require(:human_evaluation).permit(:score, :feedback)
      end
    end
  end
end
