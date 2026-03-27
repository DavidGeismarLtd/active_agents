# frozen_string_literal: true

module PromptTracker
  # Controller for managing task schedules
  class TaskSchedulesController < ApplicationController
    before_action :set_agent
    before_action :set_schedule, only: [ :edit, :update, :destroy, :toggle ]

    # GET /agents/:slug/schedules/new
    def new
      @schedule = @agent.task_schedules.build
    end

    # POST /agents/:slug/schedules
    def create
      @schedule = @agent.task_schedules.build(schedule_params)

      if @schedule.save
        redirect_to deployed_agent_path(@agent.slug), notice: "Schedule created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /agents/:slug/schedules/:id/edit
    def edit
    end

    # PATCH /agents/:slug/schedules/:id
    def update
      if @schedule.update(schedule_params)
        redirect_to deployed_agent_path(@agent.slug), notice: "Schedule updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /agents/:slug/schedules/:id
    def destroy
      @schedule.destroy
      redirect_to deployed_agent_path(@agent.slug), notice: "Schedule deleted successfully."
    end

    # POST /agents/:slug/schedules/:id/toggle
    def toggle
      @schedule.update!(enabled: !@schedule.enabled)
      redirect_to deployed_agent_path(@agent.slug),
                  notice: "Schedule #{@schedule.enabled? ? 'enabled' : 'disabled'}."
    end

    private

    def set_agent
      @agent = DeployedAgent.find_by!(slug: params[:deployed_agent_slug])

      # Only task agents can have schedules
      unless @agent.agent_type_task?
        redirect_to deployed_agent_path(@agent.slug),
                    alert: "Only task agents can have schedules."
      end
    end

    def set_schedule
      @schedule = @agent.task_schedules.find(params[:id])
    end

    def schedule_params
      params.require(:task_schedule).permit(
        :schedule_type,
        :cron_expression,
        :interval_value,
        :interval_unit,
        :timezone,
        :enabled
      )
    end
  end
end
