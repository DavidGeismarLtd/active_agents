# frozen_string_literal: true

class AddDeploymentTrackingToFunctionDefinitions < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_function_definitions, :lambda_function_name, :string
    add_column :prompt_tracker_function_definitions, :deployment_status, :string, default: "not_deployed", null: false
    add_column :prompt_tracker_function_definitions, :deployed_at, :datetime
    add_column :prompt_tracker_function_definitions, :deployment_error, :text

    add_index :prompt_tracker_function_definitions, :lambda_function_name
    add_index :prompt_tracker_function_definitions, :deployment_status
  end
end
