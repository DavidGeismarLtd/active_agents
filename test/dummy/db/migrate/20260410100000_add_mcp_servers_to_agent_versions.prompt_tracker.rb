# This migration comes from prompt_tracker (originally 20260410100000)
class AddMcpServersToAgentVersions < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_agent_versions, :mcp_servers, :jsonb, default: []
  end
end
