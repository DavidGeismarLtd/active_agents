# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Testing
    RSpec.describe DatasetsController, type: :controller do
      routes { PromptTracker::Engine.routes }

      let(:prompt) { create(:prompt) }
      let(:version) do
        create(:prompt_version,
               prompt: prompt,
               variables_schema: [
                 { "name" => "customer_name", "type" => "string", "required" => true },
                 { "name" => "issue", "type" => "string", "required" => false }
               ])
      end
      let(:dataset) { create(:dataset, prompt_version: version) }

      describe "GET #index" do
        it "returns success" do
          get :index, params: { prompt_id: prompt.id, prompt_version_id: version.id }
          expect(response).to be_successful
        end

        it "assigns @datasets" do
          dataset # create dataset
          get :index, params: { prompt_id: prompt.id, prompt_version_id: version.id }
          expect(assigns(:datasets)).to include(dataset)
        end
      end

      describe "GET #show" do
        it "returns success" do
          get :show, params: { prompt_id: prompt.id, prompt_version_id: version.id, id: dataset.id }
          expect(response).to be_successful
        end

        it "assigns @dataset" do
          get :show, params: { prompt_id: prompt.id, prompt_version_id: version.id, id: dataset.id }
          expect(assigns(:dataset)).to eq(dataset)
        end
      end

      describe "GET #new" do
        it "returns success" do
          get :new, params: { prompt_id: prompt.id, prompt_version_id: version.id }
          expect(response).to be_successful
        end

        it "assigns new @dataset" do
          get :new, params: { prompt_id: prompt.id, prompt_version_id: version.id }
          expect(assigns(:dataset)).to be_a_new(Dataset)
        end
      end

      describe "POST #create" do
        let(:valid_params) do
          {
            prompt_id: prompt.id,
            prompt_version_id: version.id,
            dataset: {
              name: "Test Dataset",
              description: "A test dataset"
            }
          }
        end

        it "creates a new dataset" do
          expect {
            post :create, params: valid_params
          }.to change(Dataset, :count).by(1)
        end

        it "redirects to dataset show page" do
          post :create, params: valid_params
          expect(response).to redirect_to(testing_prompt_prompt_version_dataset_path(prompt, version, Dataset.last))
        end

        context "with invalid params" do
          it "renders new template" do
            post :create, params: {
              prompt_id: prompt.id,
              prompt_version_id: version.id,
              dataset: { name: "" }
            }
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end
      end

      describe "GET #edit" do
        it "returns success" do
          get :edit, params: { prompt_id: prompt.id, prompt_version_id: version.id, id: dataset.id }
          expect(response).to be_successful
        end
      end

      describe "PATCH #update" do
        it "updates the dataset" do
          patch :update, params: {
            prompt_id: prompt.id,
            prompt_version_id: version.id,
            id: dataset.id,
            dataset: { name: "Updated Name" }
          }
          expect(dataset.reload.name).to eq("Updated Name")
        end

        it "redirects to dataset show page" do
          patch :update, params: {
            prompt_id: prompt.id,
            prompt_version_id: version.id,
            id: dataset.id,
            dataset: { name: "Updated Name" }
          }
          expect(response).to redirect_to(testing_prompt_prompt_version_dataset_path(prompt, version, dataset))
        end
      end

      describe "DELETE #destroy" do
        it "destroys the dataset" do
          dataset # create dataset
          expect {
            delete :destroy, params: { prompt_id: prompt.id, prompt_version_id: version.id, id: dataset.id }
          }.to change(Dataset, :count).by(-1)
        end

        it "redirects to datasets index" do
          delete :destroy, params: { prompt_id: prompt.id, prompt_version_id: version.id, id: dataset.id }
          expect(response).to redirect_to(testing_prompt_prompt_version_datasets_path(prompt, version))
        end
      end
    end
  end
end
