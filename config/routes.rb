PromptTracker::Engine.routes.draw do
  root to: "home#index"

  # ========================================
  # TESTING SECTION (Blue) - Pre-deployment validation
  # ========================================
  namespace :testing do
    get "/", to: "dashboard#index", as: :root
    post "sync_openai_assistants", to: "dashboard#sync_openai_assistants", as: :sync_openai_assistants_root

    # Standalone playground (not tied to a specific prompt)
    resource :playground, only: [ :show ], controller: "playground" do
      post :preview, on: :member
      post :save, on: :member
      post :generate, on: :member
    end

    # Prompt versions (for testing)
    resources :prompts, only: [ :index, :show ] do
      # Playground for editing existing prompts
      resource :playground, only: [ :show ], controller: "playground" do
        post :preview, on: :member
        post :save, on: :member
        post :generate, on: :member
      end

      resources :prompt_versions, only: [ :show ], path: "versions" do
        member do
          get :compare
          post :activate
        end

        # Playground for specific version
        resource :playground, only: [ :show ], controller: "playground" do
          post :preview, on: :member
          post :save, on: :member
          post :generate, on: :member
        end

        # Tests nested under prompt versions
        resources :prompt_tests, only: [ :index, :new, :create, :show, :edit, :update, :destroy ], path: "tests" do
          collection do
            post :run_all
          end
          member do
            post :run
            get :load_more_runs
          end
        end

        # Datasets nested under prompt versions
        resources :datasets, only: [ :index, :new, :create, :show, :edit, :update, :destroy ] do
          member do
            post :generate_rows # LLM-powered row generation
          end

          # Dataset rows nested under datasets
          resources :dataset_rows, only: [ :create, :update, :destroy ], path: "rows"
        end
      end
    end

    # Test runs (for viewing results)
    resources :runs, controller: "prompt_test_runs", only: [ :index, :show ] do
      # Human evaluations nested under test runs
      resources :human_evaluations, only: [ :create ]
    end

    # OpenAI Assistants
    namespace :openai do
      resources :assistants, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
        member do
          post :sync # Sync assistant from OpenAI API
        end

        # Tests nested under assistants
        resources :tests, controller: "assistant_tests", only: [ :index, :new, :create, :show, :edit, :update, :destroy ] do
          collection do
            post :run_all
          end
          member do
            post :run
            get :load_more_runs
          end
        end

        # Datasets nested under assistants
        resources :datasets, controller: "assistant_datasets", only: [ :index, :new, :create, :show, :edit, :update, :destroy ] do
          member do
            post :generate_rows # LLM-powered row generation
          end

          # Dataset rows nested under datasets
          resources :dataset_rows, only: [ :create, :update, :destroy ], path: "rows"
        end
      end
    end
  end

  # ========================================
  # MONITORING SECTION (Green) - Runtime tracking
  # ========================================
  namespace :monitoring do
    get "/", to: "dashboard#index", as: :root

    # Prompts and versions (for monitoring tracked calls)
    resources :prompts, only: [] do
      resources :prompt_versions, only: [ :show ], path: "versions"
    end

    # Evaluations (tracked/runtime calls from all environments)
    resources :evaluations, only: [ :index, :show ] do
      # Human evaluations nested under evaluations
      resources :human_evaluations, only: [ :create ]
    end

    # LLM Responses (tracked calls from all environments)
    resources :llm_responses, only: [ :index ], path: "responses" do
      # Human evaluations nested under llm_responses
      resources :human_evaluations, only: [ :create ]
    end
  end

  # Documentation
  namespace :docs do
    get :tracking
  end

  # Prompts (for monitoring - evaluator configs)
  resources :prompts, only: [] do
    # Evaluator configs nested under prompts (for monitoring)
    resources :evaluator_configs, only: [ :index, :show, :create, :update, :destroy ], path: "evaluators" do
      collection do
        post :copy_from_tests
      end
    end

    # A/B tests nested under prompts (for creating new tests)
    resources :ab_tests, only: [ :new, :create ], path: "ab-tests"
  end

  # A/B Tests (for managing tests)
  resources :ab_tests, path: "ab-tests" do
    member do
      post :start
      post :pause
      post :resume
      post :complete
      post :cancel
      get :analyze
    end
  end

  # Evaluations (used by both monitoring and test sections)
  resources :evaluations, only: [ :index, :show ] do
    # Human evaluations nested under evaluations
    resources :human_evaluations, only: [ :create ]
  end

  # Evaluator config forms (not nested, for AJAX loading)
  resources :evaluator_configs, only: [] do
    collection do
      get :config_form
    end
  end

  # Test runs (legacy, redirects to /testing/runs)
  resources :prompt_test_runs, only: [ :index, :show ], path: "test-runs"
end
