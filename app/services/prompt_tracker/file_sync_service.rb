# frozen_string_literal: true

module PromptTracker
  # Service to sync prompt YAML files to the database.
  #
  # This service reads YAML files from the configured prompts directory
  # and creates/updates Prompt and PromptVersion records in the database.
  #
  # @example Sync all files
  #   result = FileSyncService.sync_all
  #   puts "Synced #{result[:synced]} prompts"
  #
  # @example Sync a single file
  #   result = FileSyncService.sync_file("app/prompts/support/greeting.yml")
  #
  # @example Validate files without syncing
  #   result = FileSyncService.validate_all
  #   if result[:valid]
  #     puts "All files are valid!"
  #   else
  #     puts "Errors: #{result[:errors]}"
  #   end
  #
  class FileSyncService
    # Sync all YAML files from the prompts directory to the database.
    #
    # @param force [Boolean] if true, update existing prompts even if unchanged
    # @return [Hash] result with :synced, :skipped, :errors counts and details
    def self.sync_all(force: false)
      new.sync_all(force: force)
    end

    # Sync a single YAML file to the database.
    #
    # @param path [String] path to the YAML file
    # @param force [Boolean] if true, update even if unchanged
    # @return [Hash] result with :success, :prompt, :version, :error
    def self.sync_file(path, force: false)
      new.sync_file(path, force: force)
    end

    # Validate all YAML files without syncing to database.
    #
    # @return [Hash] result with :valid, :files, :errors
    def self.validate_all
      new.validate_all
    end

    # Find all YAML files in the prompts directory.
    #
    # @return [Array<String>] array of file paths
    def self.find_prompt_files
      new.find_prompt_files
    end

    # Initialize the service.
    def initialize
      @prompts_path = PromptTracker.configuration.prompts_path
    end

    # Sync all YAML files from the prompts directory to the database.
    #
    # @param force [Boolean] if true, update existing prompts even if unchanged
    # @return [Hash] result with :synced, :skipped, :errors counts and details
    def sync_all(force: false)
      files = find_prompt_files
      results = {
        synced: 0,
        skipped: 0,
        errors: 0,
        details: []
      }

      files.each do |file_path|
        result = sync_file(file_path, force: force)

        if result[:skipped]
          results[:skipped] += 1
        elsif result[:success]
          results[:synced] += 1
          results[:details] << {
            file: file_path,
            prompt: result[:prompt].name,
            version: result[:version].version_number,
            action: result[:action]
          }
        else
          results[:errors] += 1
          results[:details] << {
            file: file_path,
            error: result[:error]
          }
        end
      end

      results
    end

    # Sync a single YAML file to the database.
    #
    # @param path [String] path to the YAML file
    # @param force [Boolean] if true, update even if unchanged
    # @return [Hash] result with :success, :prompt, :version, :error
    def sync_file(path, force: false)
      # Parse the file
      prompt_file = PromptFile.new(path)

      unless prompt_file.valid?
        return {
          success: false,
          error: prompt_file.errors.join(", ")
        }
      end

      # Find or create the prompt
      prompt = Prompt.find_or_initialize_by(name: prompt_file.name)

      # Update prompt attributes
      prompt.assign_attributes(
        description: prompt_file.description,
        category: prompt_file.category,
        tags: prompt_file.tags
      )

      # Check if we need to create a new version
      needs_new_version = should_create_new_version?(prompt, prompt_file, force)

      if needs_new_version
        # Save the prompt first
        prompt.save!

        # Create new version
        version = prompt.prompt_versions.create!(
          system_prompt: prompt_file.system_prompt,
          user_prompt: prompt_file.user_prompt,
          variables_schema: prompt_file.variables,
          model_config: prompt_file.model_config,
          notes: prompt_file.notes,
          source: "file",
          status: "active"
        )

        # Activate the new version (deprecates old ones)
        version.activate!

        {
          success: true,
          prompt: prompt,
          version: version,
          action: prompt.previously_new_record? ? "created" : "updated"
        }
      else
        # No new version needed, but save prompt metadata if changed
        prompt.save! if prompt.changed?

        {
          success: true,
          skipped: true,
          prompt: prompt,
          version: prompt.active_version
        }
      end
    rescue ActiveRecord::RecordInvalid => e
      {
        success: false,
        error: "Database validation error: #{e.message}"
      }
    end

    # Validate all YAML files without syncing to database.
    #
    # @return [Hash] result with :valid, :files, :errors
    def validate_all
      files = find_prompt_files
      results = {
        valid: true,
        total: files.length,
        files: [],
        errors: []
      }

      files.each do |file_path|
        prompt_file = PromptFile.new(file_path)

        if prompt_file.valid?
          results[:files] << {
            path: file_path,
            name: prompt_file.name,
            valid: true
          }
        else
          results[:valid] = false
          results[:errors] << {
            path: file_path,
            errors: prompt_file.errors
          }
        end
      end

      results
    end

    # Find all YAML files in the prompts directory.
    #
    # @return [Array<String>] array of file paths
    def find_prompt_files
      return [] unless File.directory?(@prompts_path)

      Dir.glob(File.join(@prompts_path, "**", "*.yml"))
    end

    private

    # Determine if we should create a new version.
    #
    # @param prompt [Prompt] the prompt record
    # @param prompt_file [PromptFile] the file being synced
    # @param force [Boolean] if true, always create new version
    # @return [Boolean] true if new version should be created
    def should_create_new_version?(prompt, prompt_file, force)
      # Always create if prompt is new
      return true if prompt.new_record?

      # Always create if force is true
      return true if force

      # Get the current active version
      active_version = prompt.active_version
      return true if active_version.nil?

      # Check if user_prompt has changed
      user_prompt_changed = active_version.user_prompt != prompt_file.user_prompt

      # Check if system_prompt has changed
      system_prompt_changed = active_version.system_prompt != prompt_file.system_prompt

      # Check if variables schema has changed
      variables_changed = active_version.variables_schema != prompt_file.variables

      # Check if model config has changed
      config_changed = active_version.model_config != prompt_file.model_config

      # Create new version if any of these changed
      user_prompt_changed || system_prompt_changed || variables_changed || config_changed
    end
  end
end
