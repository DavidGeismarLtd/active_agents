# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe ContainerOrchestrator do
    let(:agent_version) { create(:agent_version, :with_chat_completions) }
    let(:deployed_agent) { create(:deployed_agent, :task_agent, agent_version: agent_version) }
    let(:task_run) { create(:task_run, :running, deployed_agent: deployed_agent) }
    let(:orchestrator) { described_class.new(task_run: task_run) }

    before do
      allow(CallbackTokenStore).to receive(:generate).and_return("test-token")
      allow(CallbackTokenStore).to receive(:revoke)
    end

    describe "#execute" do
      before do
        allow(orchestrator).to receive(:spawn_container).and_return("container-abc123")
        allow(orchestrator).to receive(:wait_for_completion)
        allow(orchestrator).to receive(:cleanup_container)
        allow(orchestrator).to receive(:cleanup_workspace)
      end

      it "sets execution_mode to containerized" do
        allow(orchestrator).to receive(:collect_output_files)
        orchestrator.execute
        expect(task_run.reload.execution_mode).to eq("containerized")
      end

      it "stores the container_id on the task run" do
        allow(orchestrator).to receive(:collect_output_files)
        orchestrator.execute
        expect(task_run.reload.container_id).to eq("container-abc123")
      end

      it "revokes the callback token on completion" do
        allow(orchestrator).to receive(:collect_output_files)
        expect(CallbackTokenStore).to receive(:revoke).with(task_run.id)
        orchestrator.execute
      end

      it "cleans up even when an error occurs" do
        allow(orchestrator).to receive(:spawn_container).and_raise(RuntimeError, "Docker not available")
        expect(orchestrator).to receive(:cleanup_container)
        expect(orchestrator).to receive(:cleanup_workspace)
        expect(CallbackTokenStore).to receive(:revoke).with(task_run.id)

        expect { orchestrator.execute }.to raise_error(RuntimeError, "Docker not available")
      end
    end

    describe "output file collection" do
      let(:output_dir) { Dir.mktmpdir }

      before do
        allow(orchestrator).to receive(:output_dir).and_return(output_dir)
      end

      after do
        FileUtils.rm_rf(output_dir)
      end

      it "attaches files from output directory" do
        File.write(File.join(output_dir, "report.csv"), "col1,col2\n1,2")
        File.write(File.join(output_dir, "summary.md"), "# Summary")

        orchestrator.send(:collect_output_files)

        task_run.reload
        expect(task_run.output_files.count).to eq(2)
        expect(task_run.output_files.map(&:filename).map(&:to_s)).to contain_exactly("report.csv", "summary.md")
      end

      it "limits to MAX_OUTPUT_FILES files" do
        (ContainerOrchestrator::MAX_OUTPUT_FILES + 5).times do |i|
          File.write(File.join(output_dir, "file_#{i}.txt"), "content #{i}")
        end

        orchestrator.send(:collect_output_files)

        task_run.reload
        expect(task_run.output_files.count).to eq(ContainerOrchestrator::MAX_OUTPUT_FILES)
      end

      it "updates metadata with file count" do
        File.write(File.join(output_dir, "output.txt"), "hello")

        orchestrator.send(:collect_output_files)

        task_run.reload
        expect(task_run.metadata["output_files_count"]).to eq(1)
      end

      it "handles empty output directory" do
        orchestrator.send(:collect_output_files)

        task_run.reload
        expect(task_run.output_files.count).to eq(0)
        expect(task_run.metadata["output_files_count"]).to eq(0)
      end

      # Regression: the orchestrator holds a TaskRun loaded BEFORE the
      # container ran. While the container runs it writes plan_update and
      # log events to task_run.metadata. Without an explicit reload, the
      # metadata merge here would clobber those writes with a stale snapshot.
      it "preserves metadata written by the container during execution" do
        # Simulate the container writing plan + logs during the run.
        TaskRun.find(task_run.id).update!(
          metadata: {
            "plan" => { "goal" => "G", "steps" => [ { "id" => "step_1", "status" => "completed" } ] },
            "logs" => [ { "level" => "info", "message" => "started" } ]
          }
        )

        File.write(File.join(output_dir, "out.txt"), "content")
        orchestrator.send(:collect_output_files)

        task_run.reload
        expect(task_run.metadata["output_files_count"]).to eq(1)
        expect(task_run.metadata["plan"]).to be_present
        expect(task_run.metadata.dig("plan", "steps").size).to eq(1)
        expect(task_run.metadata["logs"]).to be_present
      end
    end

    describe "environment building" do
      it "includes only the scoped API key for the agent's provider" do
        allow(PromptTracker.configuration).to receive(:api_key_for)
          .with(:openai).and_return("sk-test-key")

        env = orchestrator.send(:scoped_api_keys)
        expect(env).to eq({ "OPENAI_API_KEY" => "sk-test-key" })
      end

      it "returns empty hash when provider key is not configured" do
        allow(PromptTracker.configuration).to receive(:api_key_for)
          .with(:openai).and_return(nil)

        env = orchestrator.send(:scoped_api_keys)
        expect(env).to eq({})
      end
    end

    describe "workspace management" do
      it "creates input and output directories" do
        workspace = Dir.mktmpdir
        allow(orchestrator).to receive(:input_dir).and_return(File.join(workspace, "input"))
        allow(orchestrator).to receive(:output_dir).and_return(File.join(workspace, "output"))

        orchestrator.send(:prepare_workspace)

        expect(Dir.exist?(File.join(workspace, "input"))).to be true
        expect(Dir.exist?(File.join(workspace, "output"))).to be true

        FileUtils.rm_rf(workspace)
      end
    end

    describe "Docker command building" do
      it "builds a valid docker run command" do
        config = {
          image: "prompt-tracker-agent-runtime:latest",
          name: "task-run-1",
          environment: { "TASK_RUN_ID" => "1", "AGENT_CONFIG" => '{"key":"value"}' },
          volumes: [ "/tmp/input:/workspace/input:ro" ],
          memory: "512m",
          cpus: "1.0",
          network: "prompt-tracker-agent-network"
        }

        cmd = orchestrator.send(:build_docker_run_command, config)

        expect(cmd).to include("docker run -d --rm")
        expect(cmd).to include("--name task-run-1")
        expect(cmd).to include("--memory 512m")
        expect(cmd).to include("--cpus 1.0")
        expect(cmd).to include("--network prompt-tracker-agent-network")
        expect(cmd).to include("-v /tmp/input:/workspace/input:ro")
        expect(cmd).to include("prompt-tracker-agent-runtime:latest")
      end
    end
  end
end
