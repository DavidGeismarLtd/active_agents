# frozen_string_literal: true

namespace :prompt_tracker do
  namespace :functions do
    desc "Associate existing AWS Lambda functions with FunctionDefinitions"
    task associate_lambda_functions: :environment do
      puts "\n🔗 Associating existing Lambda functions with FunctionDefinitions...\n"

      # Get Lambda client
      lambda_client = PromptTracker::CodeExecutor::LambdaAdapter.build_lambda_client_static
      lambda_config = PromptTracker.configuration.function_provider_config(:aws_lambda)
      function_prefix = lambda_config[:function_prefix] || "prompt-tracker"

      # Get all Lambda functions with our prefix
      puts "📋 Fetching Lambda functions with prefix '#{function_prefix}'..."
      lambda_functions = []
      next_marker = nil

      loop do
        response = lambda_client.list_functions(
          max_items: 50,
          marker: next_marker
        )

        lambda_functions.concat(
          response.functions.select { |f| f.function_name.start_with?(function_prefix) }
        )

        break unless response.next_marker
        next_marker = response.next_marker
      end

      puts "✓ Found #{lambda_functions.size} Lambda functions\n"

      # Get all FunctionDefinitions
      function_defs = PromptTracker::FunctionDefinition.all
      puts "📋 Found #{function_defs.size} FunctionDefinitions in database\n"

      associated_count = 0
      skipped_count = 0
      error_count = 0

      function_defs.each do |func_def|
        print "  Processing '#{func_def.name}'... "

        # Generate the expected Lambda function name
        code_hash = Digest::SHA256.hexdigest(func_def.code)[0..15]
        expected_lambda_name = "#{function_prefix}-#{code_hash}"

        # Check if this Lambda function exists
        lambda_func = lambda_functions.find { |f| f.function_name == expected_lambda_name }

        if lambda_func
          # Check if already associated
          if func_def.lambda_function_name == expected_lambda_name && func_def.deployed?
            puts "already associated ✓"
            skipped_count += 1
          else
            # Associate the function
            # lambda_func.last_modified is already a Time object from AWS SDK
            deployed_at = lambda_func.last_modified.is_a?(Time) ? lambda_func.last_modified : Time.current

            func_def.update!(
              lambda_function_name: expected_lambda_name,
              deployment_status: "deployed",
              deployed_at: deployed_at,
              deployment_error: nil
            )
            puts "associated ✓"
            associated_count += 1
          end
        else
          puts "Lambda function not found (expected: #{expected_lambda_name})"
          skipped_count += 1
        end
      rescue StandardError => e
        puts "ERROR: #{e.message}"
        error_count += 1
      end

      puts "\n" + "=" * 60
      puts "✅ Association complete!"
      puts "   - Associated: #{associated_count}"
      puts "   - Skipped (already associated): #{skipped_count}"
      puts "   - Errors: #{error_count}"
      puts "=" * 60

      if associated_count > 0
        puts "\n💡 Tip: Run 'bin/rails prompt_tracker:functions:list_lambda_functions' to verify associations"
      end
    end

    desc "List all Lambda functions and their association status"
    task list_lambda_functions: :environment do
      puts "\n📋 Lambda Functions Status\n"

      # Get Lambda client
      lambda_client = PromptTracker::CodeExecutor::LambdaAdapter.build_lambda_client_static
      lambda_config = PromptTracker.configuration.function_provider_config(:aws_lambda)
      function_prefix = lambda_config[:function_prefix] || "prompt-tracker"

      # Get all Lambda functions with our prefix
      lambda_functions = []
      next_marker = nil

      loop do
        response = lambda_client.list_functions(
          max_items: 50,
          marker: next_marker
        )

        lambda_functions.concat(
          response.functions.select { |f| f.function_name.start_with?(function_prefix) }
        )

        break unless response.next_marker
        next_marker = response.next_marker
      end

      puts "Found #{lambda_functions.size} Lambda functions:\n"

      lambda_functions.each do |lambda_func|
        func_def = PromptTracker::FunctionDefinition.find_by(lambda_function_name: lambda_func.function_name)

        status = if func_def
          "✓ Associated with '#{func_def.name}'"
        else
          "⚠ Not associated with any FunctionDefinition"
        end

        puts "  #{lambda_func.function_name}"
        puts "    Status: #{status}"
        puts "    Runtime: #{lambda_func.runtime}"
        puts "    Last Modified: #{lambda_func.last_modified}"
        puts ""
      end
    end

    desc "Show expected Lambda function names for all FunctionDefinitions"
    task show_expected_names: :environment do
      puts "\n📋 Expected Lambda Function Names\n"

      lambda_config = PromptTracker.configuration.function_provider_config(:aws_lambda)
      function_prefix = lambda_config[:function_prefix] || "prompt-tracker"

      PromptTracker::FunctionDefinition.all.each do |func_def|
        code_hash = Digest::SHA256.hexdigest(func_def.code)[0..15]
        expected_name = "#{function_prefix}-#{code_hash}"

        status = case func_def.deployment_status
        when "deployed"
          "✓ Deployed"
        when "not_deployed"
          "⚠ Not deployed"
        when "deployment_failed"
          "✗ Failed"
        else
          "? Unknown"
        end

        puts "  #{func_def.name}"
        puts "    Expected Lambda name: #{expected_name}"
        puts "    Current Lambda name: #{func_def.lambda_function_name || 'none'}"
        puts "    Status: #{status}"
        puts ""
      end
    end

    desc "Reset deployment status for all functions (mark as not_deployed)"
    task reset_deployment_status: :environment do
      puts "\n🔄 Resetting deployment status for all functions...\n"

      PromptTracker::FunctionDefinition.update_all(
        deployment_status: "not_deployed",
        lambda_function_name: nil,
        deployed_at: nil,
        deployment_error: nil
      )

      count = PromptTracker::FunctionDefinition.count
      puts "✓ Reset #{count} functions to 'not_deployed' status"
    end
  end
end
