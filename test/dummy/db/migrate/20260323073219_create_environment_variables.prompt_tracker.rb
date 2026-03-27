# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20260316000001)
# Create environment_variables table for shared secrets across functions
class CreateEnvironmentVariables < ActiveRecord::Migration[7.2]
  def change
    # ============================================================================
    # TABLE: environment_variables
    # Shared environment variables (API keys, secrets) that can be reused across functions
    # ============================================================================
    create_table :prompt_tracker_environment_variables do |t|
      t.string :name, null: false  # Human-readable name (e.g., "OpenWeather API Key")
      t.string :key, null: false   # Environment variable key (e.g., "OPENWEATHER_API_KEY")
      t.text :value, null: false   # Encrypted value (e.g., "sk_abc123")
      t.text :description          # Optional description

      t.timestamps
    end

    add_index :prompt_tracker_environment_variables, :key, unique: true
    add_index :prompt_tracker_environment_variables, :name

    # ============================================================================
    # JOIN TABLE: function_definition_environment_variables
    # Many-to-many relationship between functions and shared environment variables
    # ============================================================================
    create_table :prompt_tracker_function_definition_environment_variables do |t|
      t.references :function_definition,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_function_definitions },
                   index: { name: "index_func_def_env_vars_on_func_def_id" }
      t.references :environment_variable,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_environment_variables },
                   index: { name: "index_func_def_env_vars_on_env_var_id" }

      t.timestamps
    end

    # Ensure unique combinations
    add_index :prompt_tracker_function_definition_environment_variables,
              [ :function_definition_id, :environment_variable_id ],
              unique: true,
              name: "index_func_def_env_vars_unique"
  end
end
