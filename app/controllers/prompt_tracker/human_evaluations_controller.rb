# frozen_string_literal: true

module PromptTracker
  # Controller for managing human evaluations
  class HumanEvaluationsController < ApplicationController
    before_action :set_evaluation, only: [ :create ]

    # POST /evaluations/:evaluation_id/human_evaluations
    # Create a new human evaluation for an automated evaluation
    def create
      @human_evaluation = @evaluation.human_evaluations.build(human_evaluation_params)

      if @human_evaluation.save
        redirect_to evaluation_path(@evaluation),
                    notice: "Human evaluation added successfully! Score: #{@human_evaluation.score}"
      else
        redirect_to evaluation_path(@evaluation),
                    alert: "Error creating human evaluation: #{@human_evaluation.errors.full_messages.join(', ')}"
      end
    end

    private

    def set_evaluation
      @evaluation = Evaluation.find(params[:evaluation_id])
    end

    def human_evaluation_params
      params.require(:human_evaluation).permit(:score, :feedback)
    end
  end
end
