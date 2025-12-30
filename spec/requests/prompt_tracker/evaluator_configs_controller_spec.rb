# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PromptTracker::EvaluatorConfigsController", type: :request do
  let(:prompt) { create(:prompt) }
  let(:version) { create(:prompt_version, prompt: prompt, status: "active") }
  let(:evaluator_config) do
    create(:evaluator_config,
           configurable: version,
           evaluator_key: "length",
           config: { min_length: 10, max_length: 100 })
  end

  describe "GET /evaluator_configs/config_form" do
    it "returns config form for evaluator" do
      get "/prompt_tracker/evaluator_configs/config_form", params: { evaluator_key: "length" }
      expect(response).to have_http_status(:success)
    end

    it "returns 404 for non-existent evaluator config form" do
      get "/prompt_tracker/evaluator_configs/config_form", params: { evaluator_key: "non_existent" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /prompts/:prompt_id/evaluators" do
    it "returns JSON with configs and available evaluators" do
      evaluator_config # create it
      get "/prompt_tracker/prompts/#{prompt.id}/evaluators", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json).to have_key("configs")
      expect(json).to have_key("available")
    end

    it "orders configs by creation time" do
      config1 = create(:evaluator_config, configurable: version, evaluator_key: "keyword")
      config2 = create(:evaluator_config, configurable: version, evaluator_key: "format")
      config3 = create(:evaluator_config, configurable: version, evaluator_key: "length")

      get "/prompt_tracker/prompts/#{prompt.id}/evaluators", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      config_ids = json["configs"].map { |c| c["id"] }
      expect(config_ids).to eq([ config1.id, config2.id, config3.id ])
    end
  end

  describe "GET /prompts/:prompt_id/evaluators/:id" do
    it "returns evaluator config as JSON" do
      get "/prompt_tracker/prompts/#{prompt.id}/evaluators/#{evaluator_config.id}", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["id"]).to eq(evaluator_config.id)
      expect(json["evaluator_key"]).to eq("length")
    end

    it "returns 404 for non-existent config" do
      version # ensure version exists
      get "/prompt_tracker/prompts/#{prompt.id}/evaluators/999999", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /prompts/:prompt_id/evaluators" do
    it "creates evaluator config" do
      version # ensure version exists
      expect {
        post "/prompt_tracker/prompts/#{prompt.id}/evaluators", params: {
          evaluator_config: {
            evaluator_key: "keyword",
            enabled: true,
            run_mode: "sync",
            priority: 100,
            weight: 1.0,
            config: { required_keywords: [ "hello", "world" ] }
          }
        }
      }.to change(PromptTracker::EvaluatorConfig, :count).by(1)

      expect(response).to redirect_to("/prompt_tracker/monitoring/prompts/#{prompt.id}/versions/#{version.id}#auto-evaluators")
      follow_redirect!
      expect(response.body).to include("Evaluator configured successfully")
    end

    it "creates evaluator config as JSON" do
      version # ensure version exists
      expect {
        post "/prompt_tracker/prompts/#{prompt.id}/evaluators",
             params: {
               evaluator_config: {
                 evaluator_key: "keyword",
                 enabled: true,
                 run_mode: "sync",
                 priority: 100,
                 weight: 1.0
               }
             },
             headers: { "Accept" => "application/json" }
      }.to change(PromptTracker::EvaluatorConfig, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["evaluator_key"]).to eq("keyword")
    end

    it "processes config params correctly" do
      version # ensure version exists
      post "/prompt_tracker/prompts/#{prompt.id}/evaluators", params: {
        evaluator_config: {
          evaluator_key: "keyword",
          enabled: true,
          run_mode: "sync",
          priority: 100,
          weight: 1.0,
          config: {
            required_keywords: "hello\nworld\n",
            case_sensitive: "true"
          }
        }
      }

      config = PromptTracker::EvaluatorConfig.last
      expect(config.config["required_keywords"]).to eq([ "hello", "world" ])
      expect(config.config["case_sensitive"]).to eq(true)
    end

    it "handles invalid evaluator config" do
      version # ensure version exists
      expect {
        post "/prompt_tracker/prompts/#{prompt.id}/evaluators", params: {
          evaluator_config: {
            evaluator_key: "", # Invalid - blank
            enabled: true,
            run_mode: "sync",
            priority: 100,
            weight: 1.0
          }
        }
      }.not_to change(PromptTracker::EvaluatorConfig, :count)

      expect(response).to redirect_to("/prompt_tracker/monitoring/prompts/#{prompt.id}/versions/#{version.id}#auto-evaluators")
      follow_redirect!
      expect(response.body).to include("Failed to configure evaluator")
    end

    it "handles invalid evaluator config as JSON" do
      version # ensure version exists
      expect {
        post "/prompt_tracker/prompts/#{prompt.id}/evaluators",
             params: {
               evaluator_config: {
                 evaluator_key: "",
                 enabled: true,
                 run_mode: "sync",
                 priority: 100,
                 weight: 1.0
               }
             },
             headers: { "Accept" => "application/json" }
      }.not_to change(PromptTracker::EvaluatorConfig, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json).to have_key("errors")
    end
  end

  describe "PATCH /prompts/:prompt_id/evaluators/:id" do
    it "updates evaluator config" do
      patch "/prompt_tracker/prompts/#{prompt.id}/evaluators/#{evaluator_config.id}", params: {
        evaluator_config: {
          config: { min_length: 20, max_length: 200 }
        }
      }

      expect(response).to redirect_to("/prompt_tracker/monitoring/prompts/#{prompt.id}/versions/#{version.id}#auto-evaluators")
      follow_redirect!
      expect(response.body).to include("Evaluator updated successfully")

      evaluator_config.reload
      expect(evaluator_config.config["min_length"]).to eq(20)
      expect(evaluator_config.config["max_length"]).to eq(200)
    end

    it "updates evaluator config as JSON" do
      patch "/prompt_tracker/prompts/#{prompt.id}/evaluators/#{evaluator_config.id}",
            params: { evaluator_config: { config: { min_length: 30 } } },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["config"]["min_length"]).to eq(30)
    end

    it "updates evaluator to different type" do
      patch "/prompt_tracker/prompts/#{prompt.id}/evaluators/#{evaluator_config.id}", params: {
        evaluator_config: { evaluator_key: "keyword" } # Change from length to keyword
      }

      expect(response).to redirect_to("/prompt_tracker/monitoring/prompts/#{prompt.id}/versions/#{version.id}#auto-evaluators")
      follow_redirect!
      expect(response.body).to include("Evaluator updated successfully")

      evaluator_config.reload
      expect(evaluator_config.evaluator_type).to eq("PromptTracker::Evaluators::KeywordEvaluator")
    end

    it "updates evaluator to different type as JSON" do
      patch "/prompt_tracker/prompts/#{prompt.id}/evaluators/#{evaluator_config.id}",
            params: { evaluator_config: { evaluator_key: "keyword" } },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["evaluator_type"]).to eq("PromptTracker::Evaluators::KeywordEvaluator")
    end
  end

  describe "DELETE /prompts/:prompt_id/evaluators/:id" do
    it "destroys evaluator config" do
      evaluator_config # create it first

      expect {
        delete "/prompt_tracker/prompts/#{prompt.id}/evaluators/#{evaluator_config.id}"
      }.to change(PromptTracker::EvaluatorConfig, :count).by(-1)

      expect(response).to redirect_to("/prompt_tracker/monitoring/prompts/#{prompt.id}/versions/#{version.id}#auto-evaluators")
      follow_redirect!
      expect(response.body).to include("Evaluator removed successfully")
    end

    it "destroys evaluator config as JSON" do
      evaluator_config # create it first

      expect {
        delete "/prompt_tracker/prompts/#{prompt.id}/evaluators/#{evaluator_config.id}",
               headers: { "Accept" => "application/json" }
      }.to change(PromptTracker::EvaluatorConfig, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "config processing delegation" do
    it "delegates config processing to evaluator class" do
      version # ensure version exists

      # Mock the evaluator class to verify delegation
      allow(PromptTracker::Evaluators::KeywordEvaluator).to receive(:process_params).and_call_original

      post "/prompt_tracker/prompts/#{prompt.id}/evaluators", params: {
        evaluator_config: {
          evaluator_key: "keyword",
          enabled: true,
          config: {
            required_keywords: "hello\nworld",
            case_sensitive: "true"
          }
        }
      }

      expect(PromptTracker::Evaluators::KeywordEvaluator).to have_received(:process_params)
    end

    it "uses evaluator's param_schema for type conversion" do
      version # ensure version exists

      post "/prompt_tracker/prompts/#{prompt.id}/evaluators", params: {
        evaluator_config: {
          evaluator_key: "length",
          enabled: true,
          config: {
            min_length: "50",  # String that should be converted to integer
            max_length: "500"
          }
        }
      }

      config = PromptTracker::EvaluatorConfig.last
      # Verify that the evaluator class converted the strings to integers
      expect(config.config["min_length"]).to be_a(Integer)
      expect(config.config["min_length"]).to eq(50)
      expect(config.config["max_length"]).to be_a(Integer)
      expect(config.config["max_length"]).to eq(500)
    end
  end

  describe "config processing" do
    it "processes required_keywords from textarea" do
      version # ensure version exists
      post "/prompt_tracker/prompts/#{prompt.id}/evaluators", params: {
        evaluator_config: {
          evaluator_key: "keyword",
          enabled: true,
          run_mode: "sync",
          priority: 100,
          weight: 1.0,
          config: {
            required_keywords: "hello\nworld\ntest\n"
          }
        }
      }

      config = PromptTracker::EvaluatorConfig.last
      expect(config.config["required_keywords"]).to eq([ "hello", "world", "test" ])
    end

    it "processes forbidden_keywords from textarea" do
      version # ensure version exists
      post "/prompt_tracker/prompts/#{prompt.id}/evaluators", params: {
        evaluator_config: {
          evaluator_key: "keyword",
          enabled: true,
          run_mode: "sync",
          priority: 100,
          weight: 1.0,
          config: {
            forbidden_keywords: "bad\nworse\n"
          }
        }
      }

      config = PromptTracker::EvaluatorConfig.last
      expect(config.config["forbidden_keywords"]).to eq([ "bad", "worse" ])
    end

    it "processes boolean values" do
      version # ensure version exists
      post "/prompt_tracker/prompts/#{prompt.id}/evaluators", params: {
        evaluator_config: {
          evaluator_key: "format",
          enabled: true,
          run_mode: "sync",
          priority: 100,
          weight: 1.0,
          config: {
            require_headers: "true",
            strict: "false"
          }
        }
      }

      config = PromptTracker::EvaluatorConfig.last
      expect(config.config["require_headers"]).to eq(true)
      expect(config.config["strict"]).to eq(false)
    end

    it "processes integer values" do
      version # ensure version exists
      post "/prompt_tracker/prompts/#{prompt.id}/evaluators", params: {
        evaluator_config: {
          evaluator_key: "length",
          enabled: true,
          run_mode: "sync",
          priority: 100,
          weight: 1.0,
          config: {
            min_length: "10",
            max_length: "100"
          }
        }
      }

      config = PromptTracker::EvaluatorConfig.last
      expect(config.config["min_length"]).to eq(10)
      expect(config.config["max_length"]).to eq(100)
    end

    it "processes JSON schema" do
      version # ensure version exists
      schema = { type: "object", properties: { name: { type: "string" } } }

      post "/prompt_tracker/prompts/#{prompt.id}/evaluators", params: {
        evaluator_config: {
          evaluator_key: "format",
          enabled: true,
          run_mode: "sync",
          priority: 100,
          weight: 1.0,
          config: {
            schema: schema.to_json
          }
        }
      }

      config = PromptTracker::EvaluatorConfig.last
      expect(config.config["schema"]).to eq(schema.deep_stringify_keys)
    end

    it "handles invalid JSON schema gracefully" do
      version # ensure version exists
      post "/prompt_tracker/prompts/#{prompt.id}/evaluators", params: {
        evaluator_config: {
          evaluator_key: "format",
          enabled: true,
          run_mode: "sync",
          priority: 100,
          weight: 1.0,
          config: {
            schema: "invalid json {"
          }
        }
      }

      config = PromptTracker::EvaluatorConfig.last
      expect(config.config["schema"]).to be_nil
    end
  end

  describe "POST /prompts/:prompt_id/evaluators/copy_from_tests" do
    context "when there are no tests" do
      it "redirects with alert message" do
        version # ensure version exists
        post "/prompt_tracker/prompts/#{prompt.id}/evaluators/copy_from_tests"

        expect(response).to redirect_to("/prompt_tracker/monitoring/prompts/#{prompt.id}/versions/#{version.id}#auto-evaluators")
        follow_redirect!
        expect(response.body).to include("No evaluators found in test config to copy")
      end
    end

    context "when tests have no evaluator configs" do
      before do
        create(:test, testable: version)
      end

      it "redirects with alert message" do
        post "/prompt_tracker/prompts/#{prompt.id}/evaluators/copy_from_tests"

        expect(response).to redirect_to("/prompt_tracker/monitoring/prompts/#{prompt.id}/versions/#{version.id}#auto-evaluators")
        follow_redirect!
        expect(response.body).to include("No evaluators found in test config to copy")
      end
    end

    context "when copying from tests with evaluators" do
      let!(:test) { create(:test, testable: version) }
      let!(:test_config) do
        create(:evaluator_config,
               configurable: test,
               evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
               config: { min_length: 10, max_length: 100 })
      end

      it "copies evaluators to monitoring" do
        expect {
          post "/prompt_tracker/prompts/#{prompt.id}/evaluators/copy_from_tests"
        }.to change { version.evaluator_configs.count }.by(1)
      end

      it "redirects with success message" do
        post "/prompt_tracker/prompts/#{prompt.id}/evaluators/copy_from_tests"

        expect(response).to redirect_to("/prompt_tracker/monitoring/prompts/#{prompt.id}/versions/#{version.id}#auto-evaluators")
        follow_redirect!
        expect(response.body).to include("Successfully copied 1 evaluator(s) from test config")
      end
    end

    context "when copying multiple evaluators" do
      let!(:test1) { create(:test, testable: version, name: "Test 1") }
      let!(:test2) { create(:test, testable: version, name: "Test 2") }
      let!(:config1) do
        create(:evaluator_config,
               configurable: test1,
               evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
               config: { min_length: 10 })
      end
      let!(:config2) do
        create(:evaluator_config,
               configurable: test2,
               evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator",
               config: { keywords: [ "test" ] })
      end

      it "copies all evaluators" do
        expect {
          post "/prompt_tracker/prompts/#{prompt.id}/evaluators/copy_from_tests"
        }.to change { version.evaluator_configs.count }.by(2)
      end

      it "shows correct count in success message" do
        post "/prompt_tracker/prompts/#{prompt.id}/evaluators/copy_from_tests"

        follow_redirect!
        expect(response.body).to include("Successfully copied 2 evaluator(s) from test config")
      end
    end

    context "when some evaluators already exist in monitoring" do
      let!(:test) { create(:test, testable: version) }
      let!(:test_config) do
        create(:evaluator_config,
               configurable: test,
               evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
               config: { min_length: 10 })
      end
      let!(:existing_monitoring_config) do
        create(:evaluator_config,
               configurable: version,
               evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
               config: { min_length: 50 })
      end

      it "skips duplicates" do
        expect {
          post "/prompt_tracker/prompts/#{prompt.id}/evaluators/copy_from_tests"
        }.not_to change { version.evaluator_configs.count }
      end

      it "shows skipped count in message" do
        post "/prompt_tracker/prompts/#{prompt.id}/evaluators/copy_from_tests"

        follow_redirect!
        expect(response.body).to include("No evaluators found in test config to copy")
      end
    end
  end
end
