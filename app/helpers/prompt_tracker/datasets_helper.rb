module PromptTracker
  module DatasetsHelper
    # Generate path for a dataset based on its testable type
    # @param dataset [PromptTracker::Dataset] The dataset
    # @param action [Symbol] The action (:show, :edit, :destroy)
    # @return [String] The path to the dataset
    def dataset_path(dataset, action: :show)
      testable = dataset.testable

      case testable
      when PromptTracker::PromptVersion
        prompt = testable.prompt
        case action
        when :show
          testing_prompt_prompt_version_dataset_path(prompt, testable, dataset)
        when :edit
          edit_testing_prompt_prompt_version_dataset_path(prompt, testable, dataset)
        when :destroy
          testing_prompt_prompt_version_dataset_path(prompt, testable, dataset)
        else
          raise ArgumentError, "Unknown action: #{action}"
        end
      when PromptTracker::Openai::Assistant
        case action
        when :show
          testing_openai_assistant_dataset_path(testable, dataset)
        when :edit
          edit_testing_openai_assistant_dataset_path(testable, dataset)
        when :destroy
          testing_openai_assistant_dataset_path(testable, dataset)
        else
          raise ArgumentError, "Unknown action: #{action}"
        end
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end

    # Generate index path for datasets based on testable type
    # @param testable [PromptTracker::PromptVersion, PromptTracker::Openai::Assistant] The testable
    # @return [String] The path to the datasets index
    def datasets_index_path(testable)
      case testable
      when PromptTracker::PromptVersion
        testing_prompt_prompt_version_datasets_path(testable.prompt, testable)
      when PromptTracker::Openai::Assistant
        testing_openai_assistant_datasets_path(testable)
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end

    # Generate new dataset path based on testable type
    # @param testable [PromptTracker::PromptVersion, PromptTracker::Openai::Assistant] The testable
    # @return [String] The path to create a new dataset
    def new_dataset_path(testable)
      case testable
      when PromptTracker::PromptVersion
        new_testing_prompt_prompt_version_dataset_path(testable.prompt, testable)
      when PromptTracker::Openai::Assistant
        new_testing_openai_assistant_dataset_path(testable)
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end

    # Generate path for a dataset row based on the dataset's testable type
    # @param dataset [PromptTracker::Dataset] The dataset
    # @param row [PromptTracker::DatasetRow] The row
    # @param action [Symbol] The action (:destroy, :update)
    # @return [String] The path to the dataset row
    def dataset_row_path(dataset, row, action: :destroy)
      testable = dataset.testable

      case testable
      when PromptTracker::PromptVersion
        prompt = testable.prompt
        testing_prompt_prompt_version_dataset_dataset_row_path(prompt, testable, dataset, row)
      when PromptTracker::Openai::Assistant
        testing_openai_assistant_dataset_dataset_row_path(testable, dataset, row)
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end

    # Generate path for creating dataset rows
    # @param dataset [PromptTracker::Dataset] The dataset
    # @return [String] The path to create dataset rows
    def dataset_rows_path(dataset)
      testable = dataset.testable

      case testable
      when PromptTracker::PromptVersion
        prompt = testable.prompt
        testing_prompt_prompt_version_dataset_dataset_rows_path(prompt, testable, dataset)
      when PromptTracker::Openai::Assistant
        testing_openai_assistant_dataset_dataset_rows_path(testable, dataset)
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end

    # Generate path to the testable's show page
    # @param testable [PromptTracker::PromptVersion, PromptTracker::Openai::Assistant] The testable
    # @return [String] The path to the testable
    def testable_show_path(testable)
      case testable
      when PromptTracker::PromptVersion
        testing_prompt_prompt_version_path(testable.prompt, testable)
      when PromptTracker::Openai::Assistant
        testing_openai_assistant_path(testable)
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end

    # Get display name for a testable
    # @param testable [PromptTracker::PromptVersion, PromptTracker::Openai::Assistant] The testable
    # @return [String] The display name
    def testable_name(testable)
      case testable
      when PromptTracker::PromptVersion
        testable.prompt.name
      when PromptTracker::Openai::Assistant
        testable.name
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end

    # Generate badge HTML for a testable (e.g., version number)
    # @param testable [PromptTracker::PromptVersion, PromptTracker::Openai::Assistant] The testable
    # @return [String] HTML badge or empty string
    def testable_badge(testable)
      case testable
      when PromptTracker::PromptVersion
        content_tag(:span, "v#{testable.version_number}", class: "badge bg-primary")
      when PromptTracker::Openai::Assistant
        "" # Assistants don't have version badges
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end

    # Generate path for generate_rows action
    # @param dataset [PromptTracker::Dataset] The dataset
    # @return [String] The path to generate rows
    def generate_rows_dataset_path(dataset)
      testable = dataset.testable

      case testable
      when PromptTracker::PromptVersion
        prompt = testable.prompt
        generate_rows_testing_prompt_prompt_version_dataset_path(prompt, testable, dataset)
      when PromptTracker::Openai::Assistant
        generate_rows_testing_openai_assistant_dataset_path(testable, dataset)
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end
  end
end
