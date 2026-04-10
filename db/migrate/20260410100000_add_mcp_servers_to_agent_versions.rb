class AddMcpServersToAgentVersions < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_agent_versions, :mcp_servers, :jsonb, default: []
  end
end
