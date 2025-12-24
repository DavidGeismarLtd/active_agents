# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Openai
    RSpec.describe Assistant, type: :model do
      describe "validations" do
        it "requires assistant_id" do
          assistant = build(:openai_assistant, assistant_id: nil)
          expect(assistant).not_to be_valid
          expect(assistant.errors[:assistant_id]).to include("can't be blank")
        end

        it "requires name" do
          assistant = build(:openai_assistant, name: nil)
          expect(assistant).not_to be_valid
          expect(assistant.errors[:name]).to include("can't be blank")
        end

        it "requires unique assistant_id" do
          create(:openai_assistant, assistant_id: "asst_123")
          duplicate = build(:openai_assistant, assistant_id: "asst_123")
          expect(duplicate).not_to be_valid
          expect(duplicate.errors[:assistant_id]).to include("has already been taken")
        end
      end

      describe "associations" do
        let(:assistant) { create(:openai_assistant) }

        it "has many tests" do
          test1 = create(:test, testable: assistant)
          test2 = create(:test, testable: assistant)

          expect(assistant.tests).to include(test1, test2)
          expect(assistant.tests.count).to eq(2)
        end

        it "has many datasets" do
          dataset1 = create(:dataset, testable: assistant)
          dataset2 = create(:dataset, testable: assistant)

          expect(assistant.datasets).to include(dataset1, dataset2)
          expect(assistant.datasets.count).to eq(2)
        end

        it "has many test_runs through tests" do
          test = create(:test, testable: assistant)
          test_run1 = create(:test_run, test: test)
          test_run2 = create(:test_run, test: test)

          expect(assistant.test_runs).to include(test_run1, test_run2)
          expect(assistant.test_runs.count).to eq(2)
        end

        it "destroys dependent tests when destroyed" do
          test = create(:test, testable: assistant)
          assistant.destroy

          expect(Test.exists?(test.id)).to be false
        end

        it "destroys dependent datasets when destroyed" do
          dataset = create(:dataset, testable: assistant)
          assistant.destroy

          expect(Dataset.exists?(dataset.id)).to be false
        end
      end

      describe "#fetch_from_openai!" do
        let(:assistant) { create(:openai_assistant, assistant_id: "asst_test123") }

        it "fetches assistant details from OpenAI API and stores in metadata" do
          # Mock OpenAI client response
          mock_client = double("OpenAI::Client")
          mock_response = {
            "id" => "asst_test123",
            "name" => "Updated Assistant Name",
            "description" => "Updated description",
            "instructions" => "Updated instructions",
            "model" => "gpt-4o",
            "tools" => [ { "type" => "code_interpreter" } ],
            "file_ids" => [ "file_123" ]
          }

          # Mock the OpenAI::Client constant
          stub_const("OpenAI::Client", Class.new do
            def initialize(access_token:); end
            def assistants
              @assistants ||= Object.new.tap do |obj|
                obj.define_singleton_method(:retrieve) { |id:| mock_response }
              end
            end
          end)

          assistant.fetch_from_openai!

          expect(assistant.reload.name).to eq("Updated Assistant Name")
          expect(assistant.description).to eq("Updated description")
          expect(assistant.metadata["instructions"]).to eq("Updated instructions")
          expect(assistant.metadata["model"]).to eq("gpt-4o")
          expect(assistant.metadata["tools"]).to eq([ { "type" => "code_interpreter" } ])
          expect(assistant.metadata["file_ids"]).to eq([ "file_123" ])
          expect(assistant.metadata["last_synced_at"]).to be_present
        end
      end

      describe "traits" do
        it "creates assistant with tools" do
          assistant = create(:openai_assistant, :with_tools)

          expect(assistant.metadata["tools"]).to be_present
          expect(assistant.metadata["tools"]).to include(hash_including("type" => "code_interpreter"))
          expect(assistant.metadata["tools"]).to include(hash_including("type" => "file_search"))
        end

        it "creates assistant with metadata" do
          assistant = create(:openai_assistant, :with_metadata)

          expect(assistant.metadata).to include("purpose" => "customer_support")
          expect(assistant.metadata).to include("department" => "healthcare")
          expect(assistant.metadata["instructions"]).to be_present
          expect(assistant.metadata["model"]).to eq("gpt-4o")
        end

        it "creates medical assistant" do
          assistant = create(:openai_assistant, :medical_assistant)

          expect(assistant.name).to eq("Medical Assistant")
          expect(assistant.description).to eq("Provides medical advice and support")
          expect(assistant.metadata["instructions"]).to include("medical assistant")
          expect(assistant.metadata["instructions"]).to include("empathetic")
        end

        it "creates customer support assistant" do
          assistant = create(:openai_assistant, :customer_support)

          expect(assistant.name).to eq("Customer Support Assistant")
          expect(assistant.description).to eq("Helps customers with their questions")
          expect(assistant.metadata["instructions"]).to include("customer support")
          expect(assistant.metadata["instructions"]).to include("friendly")
        end
      end

      describe "table name" do
        it "uses prompt_tracker_openai_assistants table" do
          expect(Assistant.table_name).to eq("prompt_tracker_openai_assistants")
        end
      end
    end
  end
end
