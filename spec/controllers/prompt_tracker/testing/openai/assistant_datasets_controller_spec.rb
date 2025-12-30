# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Testing
    module Openai
      RSpec.describe AssistantDatasetsController, type: :controller do
        routes { PromptTracker::Engine.routes }

        let(:assistant) { create(:openai_assistant) }
        let(:dataset) { create(:dataset, testable: assistant) }

        describe "GET #index" do
          it "returns success" do
            get :index, params: { assistant_id: assistant.id }
            expect(response).to be_successful
          end

          it "assigns @datasets" do
            dataset # create dataset
            get :index, params: { assistant_id: assistant.id }
            expect(assigns(:datasets)).to include(dataset)
          end
        end

        describe "GET #show" do
          it "returns success" do
            get :show, params: { assistant_id: assistant.id, id: dataset.id }
            expect(response).to be_successful
          end

          it "assigns @dataset" do
            get :show, params: { assistant_id: assistant.id, id: dataset.id }
            expect(assigns(:dataset)).to eq(dataset)
          end

          it "assigns @rows" do
            row = create(:dataset_row, dataset: dataset)
            get :show, params: { assistant_id: assistant.id, id: dataset.id }
            expect(assigns(:rows)).to include(row)
          end
        end

        describe "GET #new" do
          it "returns success" do
            get :new, params: { assistant_id: assistant.id }
            expect(response).to be_successful
          end

          it "assigns new @dataset" do
            get :new, params: { assistant_id: assistant.id }
            expect(assigns(:dataset)).to be_a_new(Dataset)
          end

          it "initializes dataset with empty schema (set on save)" do
            get :new, params: { assistant_id: assistant.id }
            # Schema is set by before_validation callback on create, not on build
            expect(assigns(:dataset).schema).to eq([])
          end
        end

        describe "POST #create" do
          let(:valid_params) do
            {
              assistant_id: assistant.id,
              dataset: {
                name: "Test Scenarios",
                description: "A test dataset"
              }
            }
          end

          it "creates a new dataset" do
            expect {
              post :create, params: valid_params
            }.to change(Dataset, :count).by(1)
          end

          it "sets the correct schema for assistants" do
            post :create, params: valid_params
            dataset = Dataset.last
            expect(dataset.schema.length).to eq(2)
            expect(dataset.schema[0]["name"]).to eq("interlocutor_simulation_prompt")
            expect(dataset.schema[0]["type"]).to eq("text")
            expect(dataset.schema[0]["required"]).to eq(true)
            expect(dataset.schema[1]["name"]).to eq("max_turns")
            expect(dataset.schema[1]["type"]).to eq("integer")
            expect(dataset.schema[1]["required"]).to eq(false)
          end

          it "redirects to dataset show page" do
            post :create, params: valid_params
            expect(response).to redirect_to(testing_openai_assistant_dataset_path(assistant, Dataset.last))
          end

          it "sets flash notice" do
            post :create, params: valid_params
            expect(flash[:notice]).to eq("Dataset created successfully.")
          end

          context "with invalid params" do
            it "renders new template" do
              post :create, params: {
                assistant_id: assistant.id,
                dataset: { name: "" }
              }
              expect(response).to have_http_status(:unprocessable_entity)
            end
          end
        end

        describe "GET #edit" do
          it "returns success" do
            get :edit, params: { assistant_id: assistant.id, id: dataset.id }
            expect(response).to be_successful
          end

          it "assigns @dataset" do
            get :edit, params: { assistant_id: assistant.id, id: dataset.id }
            expect(assigns(:dataset)).to eq(dataset)
          end
        end

        describe "PATCH #update" do
          let(:update_params) do
            {
              assistant_id: assistant.id,
              id: dataset.id,
              dataset: {
                name: "Updated Dataset Name",
                description: "Updated description"
              }
            }
          end

          it "updates the dataset" do
            patch :update, params: update_params
            dataset.reload
            expect(dataset.name).to eq("Updated Dataset Name")
            expect(dataset.description).to eq("Updated description")
          end

          it "redirects to dataset show page" do
            patch :update, params: update_params
            expect(response).to redirect_to(testing_openai_assistant_dataset_path(assistant, dataset))
          end

          it "sets flash notice" do
            patch :update, params: update_params
            expect(flash[:notice]).to eq("Dataset updated successfully.")
          end

          context "with invalid params" do
            it "renders edit template" do
              patch :update, params: {
                assistant_id: assistant.id,
                id: dataset.id,
                dataset: { name: "" }
              }
              expect(response).to have_http_status(:unprocessable_entity)
            end
          end
        end

        describe "DELETE #destroy" do
          it "destroys the dataset" do
            dataset # create dataset
            expect {
              delete :destroy, params: { assistant_id: assistant.id, id: dataset.id }
            }.to change(Dataset, :count).by(-1)
          end

          it "redirects to datasets index" do
            delete :destroy, params: { assistant_id: assistant.id, id: dataset.id }
            expect(response).to redirect_to(testing_openai_assistant_datasets_path(assistant))
          end

          it "sets flash notice" do
            delete :destroy, params: { assistant_id: assistant.id, id: dataset.id }
            expect(flash[:notice]).to eq("Dataset deleted successfully.")
          end
        end

        describe "POST #generate_rows" do
          it "enqueues GenerateDatasetRowsJob" do
            expect {
              post :generate_rows, params: {
                assistant_id: assistant.id,
                id: dataset.id,
                count: 5,
                instructions: "Generate conversation scenarios",
                model: "gpt-4o"
              }
            }.to have_enqueued_job(GenerateDatasetRowsJob).with(
              dataset.id,
              count: 5,
              instructions: "Generate conversation scenarios",
              model: "gpt-4o"
            )
          end

          it "redirects to dataset show page" do
            post :generate_rows, params: {
              assistant_id: assistant.id,
              id: dataset.id,
              count: 5
            }
            expect(response).to redirect_to(testing_openai_assistant_dataset_path(assistant, dataset))
          end

          it "sets flash notice with count" do
            post :generate_rows, params: {
              assistant_id: assistant.id,
              id: dataset.id,
              count: 5
            }
            expect(flash[:notice]).to eq("Generating 5 rows in the background. Rows will appear shortly.")
          end
        end
      end
    end
  end
end
