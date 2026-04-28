# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe TaskRun, type: :model do
    describe "execution_mode" do
      let(:task_run) { create(:task_run) }

      it "defaults to in_process" do
        expect(task_run.execution_mode).to eq("in_process")
      end

      it "can be set to containerized" do
        task_run.update!(execution_mode: "containerized")
        expect(task_run.reload.execution_mode).to eq("containerized")
      end

      it "provides enum query methods" do
        expect(task_run.execution_mode_in_process?).to be true
        expect(task_run.execution_mode_containerized?).to be false
      end
    end

    describe "output_files" do
      let(:task_run) { create(:task_run) }

      it "can have files attached" do
        task_run.output_files.attach(
          io: StringIO.new("col1,col2\n1,2"),
          filename: "report.csv",
          content_type: "text/csv"
        )

        expect(task_run.output_files).to be_attached
        expect(task_run.output_files.count).to eq(1)
        expect(task_run.output_files.first.filename.to_s).to eq("report.csv")
      end

      it "can have multiple files attached" do
        task_run.output_files.attach(
          io: StringIO.new("data"),
          filename: "file1.txt",
          content_type: "text/plain"
        )
        task_run.output_files.attach(
          io: StringIO.new("more data"),
          filename: "file2.txt",
          content_type: "text/plain"
        )

        expect(task_run.output_files.count).to eq(2)
      end
    end
  end
end
