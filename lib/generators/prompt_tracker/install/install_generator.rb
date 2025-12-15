# frozen_string_literal: true

module PromptTracker
  module Generators
    # Generator to install PromptTracker in a Rails application.
    #
    # Usage:
    #   rails generate prompt_tracker:install
    #
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates PromptTracker initializer and prompts directory"

      def copy_initializer
        template "prompt_tracker.rb", "config/initializers/prompt_tracker.rb"
      end

      def create_prompts_directory
        empty_directory "app/prompts"
        create_file "app/prompts/.keep", ""
      end

      def show_readme
        readme "README" if behavior == :invoke
      end
    end
  end
end
