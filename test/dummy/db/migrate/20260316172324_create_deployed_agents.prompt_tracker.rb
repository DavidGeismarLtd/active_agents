# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20260316000002)
# Create deployed_agents and agent_conversations tables for agent deployment
class CreateDeployedAgents < ActiveRecord::Migration[7.2]
  def change
    # ============================================================================
    # TABLE: deployed_agents
    # Deployed prompt versions accessible via unique URLs
    # ============================================================================
    create_table :prompt_tracker_deployed_agents do |t|
      t.references :prompt_version,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_prompt_versions },
                   index: true

      t.string :name, null: false
      t.string :slug, null: false
      t.string :status, null: false, default: "active"
      t.jsonb :deployment_config, default: {}, null: false
      t.datetime :deployed_at
      t.datetime :paused_at
      t.text :error_message
      t.integer :request_count, default: 0, null: false
      t.datetime :last_request_at
      t.string :created_by
      t.string :api_key_digest  # Hashed API key for authentication

      t.timestamps
    end

    add_index :prompt_tracker_deployed_agents, :slug, unique: true
    add_index :prompt_tracker_deployed_agents, :status
    add_index :prompt_tracker_deployed_agents, :created_at

    # ============================================================================
    # TABLE: agent_conversations
    # Conversation state for deployed agents
    # ============================================================================
    create_table :prompt_tracker_agent_conversations do |t|
      t.references :deployed_agent,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_deployed_agents },
                   index: true

      t.string :conversation_id, null: false
      t.jsonb :messages, default: [], null: false
      t.jsonb :metadata, default: {}, null: false
      t.datetime :last_message_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :prompt_tracker_agent_conversations,
              [ :deployed_agent_id, :conversation_id ],
              unique: true,
              name: "index_agent_conversations_on_agent_and_conversation"
    add_index :prompt_tracker_agent_conversations, :expires_at
    add_index :prompt_tracker_agent_conversations, :last_message_at

    # ============================================================================
    # JOIN TABLE: deployed_agent_functions
    # Many-to-many relationship between deployed agents and function definitions
    # ============================================================================
    create_table :prompt_tracker_deployed_agent_functions do |t|
      t.references :deployed_agent,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_deployed_agents },
                   index: { name: "index_deployed_agent_funcs_on_agent_id" }
      t.references :function_definition,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_function_definitions },
                   index: { name: "index_deployed_agent_funcs_on_func_def_id" }

      t.timestamps
    end

    add_index :prompt_tracker_deployed_agent_functions,
              [ :deployed_agent_id, :function_definition_id ],
              unique: true,
              name: "index_deployed_agent_functions_unique"

    # ============================================================================
    # Update function_executions to track deployed agent context
    # ============================================================================
    add_reference :prompt_tracker_function_executions,
                  :deployed_agent,
                  foreign_key: { to_table: :prompt_tracker_deployed_agents },
                  index: true

    add_reference :prompt_tracker_function_executions,
                  :agent_conversation,
                  foreign_key: { to_table: :prompt_tracker_agent_conversations },
                  index: true

    # ============================================================================
    # Update llm_responses to track deployed agent context
    # ============================================================================
    add_reference :prompt_tracker_llm_responses,
                  :deployed_agent,
                  foreign_key: { to_table: :prompt_tracker_deployed_agents },
                  index: true

    add_reference :prompt_tracker_llm_responses,
                  :agent_conversation,
                  foreign_key: { to_table: :prompt_tracker_agent_conversations },
                  index: true
  end
end
