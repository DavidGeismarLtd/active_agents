# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20260320000001)
# Add task agent support to deployed_agents table
# Extends the deployed_agents table to support both conversational and task agents
class AddTaskAgentSupportToDeployedAgents < ActiveRecord::Migration[7.2]
  def change
    # Add agent_type to distinguish between conversational and task agents
    add_column :prompt_tracker_deployed_agents,
               :agent_type,
               :string,
               default: "conversational",
               null: false

    # Add task_config for task-specific configuration
    add_column :prompt_tracker_deployed_agents,
               :task_config,
               :jsonb,
               default: {},
               null: false

    # Add index for filtering by agent type
    add_index :prompt_tracker_deployed_agents, :agent_type
  end
end
