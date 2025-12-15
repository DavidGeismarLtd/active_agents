# frozen_string_literal: true

module PromptTracker
  module Monitoring
    # Controller for managing human evaluations in monitoring context
    class HumanEvaluationsController < ApplicationController
      before_action :set_evaluation, only: [ :create ], if: -> { params[:evaluation_id].present? }
      before_action :set_llm_response, only: [ :create ], if: -> { params[:llm_response_id].present? }

      # POST /monitoring/evaluations/:evaluation_id/human_evaluations
      # Create a new human evaluation for an automated evaluation
      #
      # POST /monitoring/llm_responses/:llm_response_id/human_evaluations
      # Create a new human evaluation directly for an LLM response
      def create
        if @evaluation
          @human_evaluation = @evaluation.human_evaluations.build(human_evaluation_params)
          redirect_path = monitoring_evaluation_path(@evaluation)
          modal_id = "human-evaluation-modal-#{@evaluation.id}"
        elsif @llm_response
          @human_evaluation = @llm_response.human_evaluations.build(human_evaluation_params)
          redirect_path = monitoring_root_path
          modal_id = "human-evaluation-modal-#{@llm_response.id}"
        else
          redirect_to monitoring_root_path, alert: "Invalid request"
          return
        end

        if @human_evaluation.save
          respond_to do |format|
            format.turbo_stream do
              # Close the modal properly using custom Turbo Stream action
              render turbo_stream: [
                turbo_stream.action(:close_modal, modal_id),
                turbo_stream.append("flash-messages", partial: "prompt_tracker/shared/flash",
                                    locals: { type: "notice", message: "Human evaluation added successfully! Score: #{@human_evaluation.score}" })
              ]
            end
            format.html do
              redirect_to redirect_path,
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
              redirect_to redirect_path,
                          alert: "Error creating human evaluation: #{@human_evaluation.errors.full_messages.join(', ')}"
            end
          end
        end
      end

      private

      def set_evaluation
        @evaluation = Evaluation.tracked.find(params[:evaluation_id])
      end

      def set_llm_response
        @llm_response = LlmResponse.tracked_calls.find(params[:llm_response_id])
      end

      def human_evaluation_params
        params.require(:human_evaluation).permit(:score, :feedback)
      end
    end
  end
end
