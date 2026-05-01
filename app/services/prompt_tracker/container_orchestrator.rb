# frozen_string_literal: true

module PromptTracker
  # Orchestrates Docker container lifecycle for task agent execution.
  #
  # This service:
  # 1. Prepares host directories (input/output volumes)
  # 2. Builds container configuration (env vars, volumes, resource limits)
  # 3. Spawns and monitors the container
  # 4. Collects output files after container exits
  # 5. Attaches output files to TaskRun via Active Storage
  # 6. Cleans up host temp directories
  #
  # @example Execute a task run in a container
  #   ContainerOrchestrator.new(task_run: task_run).execute
  #
  class ContainerOrchestrator
    HOST_WORKSPACE_ROOT = "/tmp/prompt_tracker/task_runs"
    MAX_OUTPUT_SIZE_BYTES = 100.megabytes
    MAX_SINGLE_FILE_BYTES = 25.megabytes
    MAX_OUTPUT_FILES = 50

    def initialize(task_run:)
      @task_run = task_run
      @task_agent = task_run.deployed_agent
      @container_id = nil
      @host_workspace = File.join(HOST_WORKSPACE_ROOT, task_run.id.to_s)
    end

    def execute
      @task_run.update!(execution_mode: "containerized")

      prepare_workspace
      container_config = build_container_config
      @container_id = spawn_container(container_config)
      @task_run.update!(container_id: @container_id)
      wait_for_completion
      collect_output_files
    ensure
      cleanup_container
      cleanup_workspace
      CallbackTokenStore.revoke(@task_run.id)
    end

    private

    def prepare_workspace
      FileUtils.mkdir_p(input_dir)
      FileUtils.mkdir_p(output_dir)
      copy_input_files if task_run_has_input_files?
    end

    def build_container_config
      {
        image: config.agent_runtime_image,
        name: "task-run-#{@task_run.id}",
        environment: build_environment,
        volumes: build_volumes,
        memory: resource_limits[:memory],
        cpus: resource_limits[:cpus],
        network: "prompt-tracker-agent-network"
      }
    end

    def build_environment
      agent_config = serialize_agent_config
      callback_token = CallbackTokenStore.generate(
        @task_run.id,
        ttl_seconds: resource_limits[:timeout_seconds] + 300
      )

      env = {
        "TASK_RUN_ID" => @task_run.id.to_s,
        "AGENT_CONFIG" => agent_config.to_json,
        "CALLBACK_URL" => callback_url,
        "CALLBACK_TOKEN" => callback_token
      }
      env.merge!(scoped_api_keys)
      env.merge!(scoped_aws_keys) if @task_agent.function_definitions.any?
      env
    end

    def build_volumes
      [
        "#{input_dir}:/workspace/input:ro",
        "#{output_dir}:/workspace/output:rw"
      ]
    end

    def serialize_agent_config
      agent_version = @task_agent.agent_version

      {
        system_prompt: agent_version.system_prompt,
        model_config: agent_version.model_config,
        variables: @task_run.variables_used,
        functions: serialize_functions,
        mcp_servers: agent_version.mcp_servers || [],
        planning: @task_agent.task_configuration[:planning] || {},
        execution: {
          max_iterations: @task_agent.task_configuration.dig(:execution, :max_iterations) || 5,
          timeout_seconds: resource_limits[:timeout_seconds]
        },
        initial_prompt: @task_agent.task_config[:initial_prompt]
      }
    end

    def serialize_functions
      @task_agent.function_definitions.map do |fn|
        {
          name: fn.name,
          description: fn.description,
          parameters: fn.parameters,
          lambda_function_name: fn.lambda_function_name
        }
      end
    end

    def scoped_api_keys
      provider = @task_agent.agent_version.model_config["provider"]
      key_mapping = {
        "openai" => "OPENAI_API_KEY",
        "anthropic" => "ANTHROPIC_API_KEY",
        "google" => "GEMINI_API_KEY",
        "gemini" => "GEMINI_API_KEY",
        "deepseek" => "DEEPSEEK_API_KEY",
        "mistral" => "MISTRAL_API_KEY"
      }
      key_name = key_mapping[provider]
      return {} unless key_name

      api_key = PromptTracker.configuration.api_key_for(provider.to_sym)
      api_key ? { key_name => api_key } : {}
    end

    def scoped_aws_keys
      aws_config = PromptTracker.configuration.function_provider_config(:aws_lambda)
      return {} unless aws_config

      {
        "AWS_ACCESS_KEY_ID" => aws_config[:access_key_id],
        "AWS_SECRET_ACCESS_KEY" => aws_config[:secret_access_key],
        "AWS_REGION" => aws_config[:region] || "us-east-1"
      }.compact
    end

    def spawn_container(container_config)
      cmd = build_docker_run_command(container_config)
      Rails.logger.info(safe_spawn_log_message(container_config))

      output = `#{cmd} 2>&1`.strip
      unless $?.success?
        raise "Failed to spawn container: #{output}"
      end

      container_id = output.lines.last&.strip
      Rails.logger.info "[ContainerOrchestrator] Container started: #{container_id}"
      container_id
    end

    # Structured, credential-safe log line for container spawn.
    #
    # The raw `docker run` command embeds env-var VALUES as plaintext `-e`
    # flags — those values include CALLBACK_TOKEN, OPENAI_API_KEY,
    # AWS_SECRET_ACCESS_KEY, etc. Logging the command verbatim leaks
    # credentials into app log aggregators. This helper returns env *keys*
    # only, never values.
    def safe_spawn_log_message(container_config)
      "[ContainerOrchestrator] Spawning container for TaskRun #{@task_run.id} " \
        "(image=#{container_config[:image]}, name=#{container_config[:name]}, " \
        "env_keys=[#{container_config[:environment].keys.sort.join(', ')}], " \
        "volumes=[#{container_config[:volumes].join(', ')}])"
    end

    def build_docker_run_command(container_config)
      parts = [ "docker", "run", "-d", "--rm" ]
      parts += [ "--name", container_config[:name] ]
      parts += [ "--memory", container_config[:memory] ] if container_config[:memory]
      parts += [ "--cpus", container_config[:cpus] ] if container_config[:cpus]
      parts += [ "--network", container_config[:network] ]

      container_config[:environment].each do |key, value|
        parts += [ "-e", "#{key}=#{Shellwords.escape(value)}" ]
      end

      container_config[:volumes].each do |volume|
        parts += [ "-v", volume ]
      end

      parts << container_config[:image]
      parts.join(" ")
    end

    def wait_for_completion
      timeout = resource_limits[:timeout_seconds]
      deadline = Time.current + timeout

      loop do
        unless container_running?
          Rails.logger.info "[ContainerOrchestrator] Container exited for TaskRun #{@task_run.id}"
          check_container_exit_code
          return
        end

        if Time.current > deadline
          Rails.logger.warn "[ContainerOrchestrator] Container timeout for TaskRun #{@task_run.id}"
          kill_container
          @task_run.fail!(error: "Container execution timed out after #{timeout} seconds") unless @task_run.finished?
          return
        end

        sleep 5
      end
    end

    def container_running?
      output = `docker inspect -f '{{.State.Running}}' #{@container_id} 2>&1`.strip
      output == "true"
    end

    def check_container_exit_code
      output = `docker inspect -f '{{.State.ExitCode}}' #{@container_id} 2>/dev/null`.strip
      exit_code = output.to_i

      if exit_code != 0 && !@task_run.finished?
        logs = `docker logs #{@container_id} --tail 50 2>&1`.strip
        @task_run.fail!(error: "Container exited with code #{exit_code}. Last logs:\n#{logs}")
      end
    end

    def kill_container
      system("docker kill #{@container_id} 2>/dev/null")
    end

    def collect_output_files
      files = validate_output_files
      files_attached = 0

      output_path = Pathname.new(output_dir)
      files.each do |file_path|
        relative_path = Pathname.new(file_path).relative_path_from(output_path)

        @task_run.output_files.attach(
          io: File.open(file_path),
          filename: relative_path.to_s,
          content_type: Marcel::MimeType.for(Pathname.new(file_path))
        )
        files_attached += 1
      end

      # Reload before merging — the container has been writing to metadata
      # (plan_update events, log events) while we held this stale @task_run.
      # Without reload we'd clobber the plan with our pre-run snapshot.
      @task_run.reload
      @task_run.update!(
        metadata: (@task_run.metadata || {}).merge("output_files_count" => files_attached)
      )

      Rails.logger.info "[ContainerOrchestrator] Attached #{files_attached} output files to TaskRun #{@task_run.id}"
    end

    def validate_output_files
      files = Dir.glob(File.join(output_dir, "**", "*")).select { |f| File.file?(f) }
      return [] if files.empty?

      if files.count > MAX_OUTPUT_FILES
        Rails.logger.warn "[ContainerOrchestrator] Too many output files (#{files.count}). Only first #{MAX_OUTPUT_FILES} will be attached."
        files = files.first(MAX_OUTPUT_FILES)
      end

      total_size = files.sum { |f| File.size(f) }
      if total_size > MAX_OUTPUT_SIZE_BYTES
        Rails.logger.warn "[ContainerOrchestrator] Total output size #{total_size} exceeds limit. Skipping large files."
        files = files.reject { |f| File.size(f) > MAX_SINGLE_FILE_BYTES }
      end

      files
    end

    def cleanup_container
      return unless @container_id

      # Force remove if still present (--rm should handle this, but be safe)
      system("docker rm -f #{@container_id} 2>/dev/null")
    end

    def cleanup_workspace
      FileUtils.rm_rf(@host_workspace)
    end

    def task_run_has_input_files?
      input_files = @task_run.variables_used["input_files"]
      input_files.is_a?(Array) && input_files.any?
    end

    def copy_input_files
      input_files = @task_run.variables_used["input_files"] || []
      input_files.each do |file_ref|
        case file_ref["type"]
        when "url"
          download_file(file_ref["url"], File.join(input_dir, file_ref["filename"]))
        when "active_storage"
          blob = ActiveStorage::Blob.find_signed(file_ref["signed_id"])
          File.open(File.join(input_dir, blob.filename.to_s), "wb") do |f|
            blob.download { |chunk| f.write(chunk) }
          end
        end
      end
    end

    def download_file(url, destination)
      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)
      File.binwrite(destination, response.body)
    end

    def callback_url
      base = PromptTracker.configuration.agent_base_url.to_s.sub(%r{/+\z}, "")
      path = PromptTracker.configuration.agent_callback_path.to_s
      path = "/#{path}" unless path.start_with?("/")
      "#{base}#{path}"
    end

    def resource_limits
      PromptTracker.configuration.container_resource_limits
    end

    def config
      PromptTracker.configuration
    end

    def input_dir
      File.join(@host_workspace, "input")
    end

    def output_dir
      File.join(@host_workspace, "output")
    end
  end
end
