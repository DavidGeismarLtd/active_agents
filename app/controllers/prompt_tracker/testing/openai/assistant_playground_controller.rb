# frozen_string_literal: true

module PromptTracker
  module Testing
    module Openai
      # Controller for the OpenAI Assistant Playground.
      #
      # Provides an interactive interface for creating, editing, and testing
      # OpenAI Assistants with a split-screen layout:
      # - Left: Thread chat interface for testing
      # - Right: Configuration sidebar for assistant settings
      #
      class AssistantPlaygroundController < ApplicationController
        before_action :set_assistant, only: [
          :show, :update_assistant, :send_message, :load_messages,
          :upload_file, :list_files, :delete_file,
          :create_vector_store, :list_vector_stores, :attach_vector_store, :add_file_to_vector_store
        ]
        before_action :initialize_service

        # GET /testing/openai/assistants/playground/new
        #
        # Renders the playground interface for creating a new assistant
        def new
          @assistant = PromptTracker::Openai::Assistant.new
          @is_new = true
          load_available_models

          render :show
        end

        # GET /testing/openai/assistants/:assistant_id/playground
        #
        # Renders the playground interface for editing an existing assistant
        def show
          @assistant ||= PromptTracker::Openai::Assistant.new
          @is_new = @assistant.new_record?
          load_available_models
        end

        # POST /testing/openai/assistants/playground/create_assistant
        #
        # Creates a new assistant via OpenAI API
        def create_assistant
          result = @service.create_assistant(assistant_params)

          if result[:success]
            render json: {
              success: true,
              assistant_id: result[:assistant].assistant_id,
              message: "Assistant created successfully",
              redirect_url: testing_openai_assistant_playground_path(result[:assistant])
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # POST /testing/openai/assistants/:assistant_id/playground/update_assistant
        #
        # Updates an existing assistant via OpenAI API
        def update_assistant
          result = @service.update_assistant(@assistant.assistant_id, assistant_params)

          if result[:success]
            render json: {
              success: true,
              message: "Assistant updated successfully",
              last_saved_at: Time.current.strftime("%I:%M %p")
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # POST /testing/openai/assistants/:assistant_id/playground/create_thread
        #
        # Creates a new conversation thread
        def create_thread
          result = @service.create_thread

          if result[:success]
            session[:playground_thread_id] = result[:thread_id]
            render json: {
              success: true,
              thread_id: result[:thread_id]
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # POST /testing/openai/assistants/:assistant_id/playground/send_message
        #
        # Sends a message in the thread and runs the assistant
        def send_message
          thread_id = params[:thread_id] || session[:playground_thread_id]

          # Auto-create thread if needed
          if thread_id.blank?
            thread_result = @service.create_thread
            return render json: { success: false, error: "Failed to create thread" },
                          status: :unprocessable_entity unless thread_result[:success]
            thread_id = thread_result[:thread_id]
            session[:playground_thread_id] = thread_id
          end

          result = @service.send_message(
            thread_id: thread_id,
            assistant_id: @assistant.assistant_id,
            content: params[:content]
          )

          if result[:success]
            render json: {
              success: true,
              thread_id: thread_id,
              message: result[:message],
              usage: result[:usage]
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # GET /testing/openai/assistants/:assistant_id/playground/load_messages
        #
        # Loads message history for a thread
        def load_messages
          thread_id = params[:thread_id] || session[:playground_thread_id]

          if thread_id.blank?
            return render json: { success: true, messages: [] }
          end

          result = @service.load_messages(thread_id: thread_id)

          if result[:success]
            render json: {
              success: true,
              messages: result[:messages]
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # POST /testing/openai/assistants/:assistant_id/playground/upload_file
        #
        # Uploads a file to OpenAI for use with file_search
        def upload_file
          unless params[:file].present?
            return render json: { success: false, error: "No file provided" }, status: :unprocessable_entity
          end

          result = @service.upload_file(params[:file])

          if result[:success]
            render json: {
              success: true,
              file: result[:file]
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # GET /testing/openai/assistants/:assistant_id/playground/list_files
        #
        # Lists files uploaded for assistants
        def list_files
          result = @service.list_files

          if result[:success]
            render json: {
              success: true,
              files: result[:files]
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # DELETE /testing/openai/assistants/:assistant_id/playground/delete_file
        #
        # Deletes a file from OpenAI
        def delete_file
          result = @service.delete_file(params[:file_id])

          if result[:success]
            render json: { success: true }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # POST /testing/openai/assistants/:assistant_id/playground/create_vector_store
        #
        # Creates a vector store for file_search
        def create_vector_store
          result = @service.create_vector_store(
            name: params[:name] || "Playground Vector Store",
            file_ids: params[:file_ids] || []
          )

          if result[:success]
            render json: {
              success: true,
              vector_store: result[:vector_store]
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # GET /testing/openai/assistants/:assistant_id/playground/list_vector_stores
        #
        # Lists vector stores
        def list_vector_stores
          result = @service.list_vector_stores

          if result[:success]
            render json: {
              success: true,
              vector_stores: result[:vector_stores]
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # POST /testing/openai/assistants/:assistant_id/playground/add_file_to_vector_store
        #
        # Adds a file to a vector store
        def add_file_to_vector_store
          result = @service.add_file_to_vector_store(
            vector_store_id: params[:vector_store_id],
            file_id: params[:file_id]
          )

          if result[:success]
            render json: {
              success: true,
              vector_store_file: result[:vector_store_file]
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # POST /testing/openai/assistants/:assistant_id/playground/attach_vector_store
        #
        # Attaches a vector store to an assistant
        def attach_vector_store
          result = @service.attach_vector_store_to_assistant(
            assistant_id: @assistant.assistant_id,
            vector_store_ids: Array(params[:vector_store_ids])
          )

          if result[:success]
            render json: { success: true }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        private

        def set_assistant
          @assistant = PromptTracker::Openai::Assistant.find(params[:assistant_id]) if params[:assistant_id] != "new"
        end

        def initialize_service
          @service = AssistantPlaygroundService.new
        end

        def assistant_params
          params.require(:assistant).permit(
            :name,
            :description,
            :instructions,
            :model,
            :temperature,
            :top_p,
            :response_format,
            tools: [],
            metadata: {}
          )
        end

        def load_available_models
          # Get OpenAI models from configuration for assistant playground context
          @available_models = PromptTracker.configuration.models_for(:assistant_playground, provider: :openai)

          # Fallback to default models if none configured
          if @available_models.blank?
            @available_models = [
              { id: "gpt-4o", name: "GPT-4o" },
              { id: "gpt-4-turbo", name: "GPT-4 Turbo" },
              { id: "gpt-4", name: "GPT-4" },
              { id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo" }
            ]
          end
        end
      end
    end
  end
end
