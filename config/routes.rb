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

        # Datasets nested under prompt versions
        resources :datasets, only: [ :index, :new, :create, :show, :edit, :update, :destroy ] do
          member do
            post :generate_rows # LLM-powered row generation
          end

          # Dataset rows nested under datasets
          resources :dataset_rows, only: [ :create, :update, :destroy ], path: "rows" do
            collection do
              delete :batch_destroy
            end
          end
        end
      end
    end

    # Tests for prompt versions (not nested under prompts for simpler URLs)
    resources :prompt_versions, only: [], path: "versions" do
      resources :tests, only: [ :create, :update, :destroy ] do
        collection do
          post :run_all
        end
        member do
          post :run
          get :load_more_runs
        end
      end
    end

    # Test runs (for viewing results)
    resources :runs, controller: "test_runs" do
      # Human evaluations nested under test runs
      resources :human_evaluations, only: [ :create ]
    end

    # OpenAI Assistants
    namespace :openai do
      # Standalone playground route for creating new assistants
      get "assistants/playground/new", to: "assistant_playground#new", as: "new_assistant_playground"

      resources :assistants, only: [ :index, :show, :destroy ] do
        member do
          post :sync # Sync assistant from OpenAI API
        end

        # Playground for editing existing assistants
        resource :playground, only: [ :show ], controller: "assistant_playground" do
          post :create_assistant    # Create new assistant via API
          post :update_assistant    # Update existing assistant via API
          post :send_message        # Send message in thread
          post :create_thread       # Create new thread
          get  :load_messages       # Load thread messages

          # File management for file_search
          post :upload_file              # Upload file to OpenAI
          get  :list_files               # List uploaded files
          delete :delete_file            # Delete a file
          post :create_vector_store      # Create a vector store
          get  :list_vector_stores       # List vector stores
          post :add_file_to_vector_store # Add file to vector store
          post :attach_vector_store      # Attach vector store to assistant
        end

        # Tests nested under assistants
        resources :tests, controller: "assistant_tests", only: [ :create, :show, :update, :destroy ] do
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
          resources :dataset_rows, only: [ :create, :update, :destroy ], path: "rows" do
            collection do
              delete :batch_destroy
            end
          end
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
end
