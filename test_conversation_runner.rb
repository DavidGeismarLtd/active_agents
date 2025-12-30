#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test script for ConversationRunner
# Run with: ruby test_conversation_runner.rb

# Load the dummy Rails app environment
require_relative "test/dummy/config/environment"

puts "=" * 80
puts "Testing ConversationRunner with Real OpenAI API"
puts "=" * 80
puts

# Configuration
ASSISTANT_ID = "asst_Rp8RFTBJuMsJgtPaODCFsalw"
INTERLOCUTOR_PROMPT = <<~PROMPT
  You are simulating a patient talking to a medical assistant.
  You have a severe headache and are seeking medical advice.
  Respond naturally to the assistant's questions.
  Keep your responses concise (1-2 sentences).
  After 2-3 exchanges, say you feel better and thank the assistant.
PROMPT
MAX_TURNS = 3

puts "Configuration:"
puts "  Assistant ID: #{ASSISTANT_ID}"
puts "  Max Turns: #{MAX_TURNS}"
puts "  API Key: #{ENV['OPENAI_LOUNA_API_KEY'] ? 'Set ✓' : 'NOT SET ✗'}"
puts

unless ENV["OPENAI_LOUNA_API_KEY"]
  puts "ERROR: OPENAI_LOUNA_API_KEY environment variable not set!"
  exit 1
end

# Create runner
runner = PromptTracker::Openai::ConversationRunner.new(
  assistant_id: ASSISTANT_ID,
  interlocutor_simulation_prompt: INTERLOCUTOR_PROMPT,
  max_turns: MAX_TURNS
)

puts "Starting conversation..."
puts "-" * 80
puts

begin
  result = runner.run!

  puts "\n" + "=" * 80
  puts "CONVERSATION COMPLETED"
  puts "=" * 80
  puts
  puts "Status: #{result[:status]}"
  puts "Thread ID: #{result[:thread_id]}"
  puts "Total Turns: #{result[:total_turns]}"
  puts "Total Messages: #{result[:messages].count}"
  puts

  puts "=" * 80
  puts "CONVERSATION TRANSCRIPT"
  puts "=" * 80

  result[:messages].each_with_index do |msg, index|
    puts
    puts "[#{index + 1}] #{msg[:role].upcase} (Turn #{msg[:turn]})"
    puts "Time: #{msg[:timestamp]}"
    puts "-" * 80
    puts msg[:content]
    puts "-" * 80
  end

  puts
  puts "=" * 80
  puts "METADATA"
  puts "=" * 80
  puts JSON.pretty_generate(result[:metadata])
  puts "=" * 80

  puts
  puts "✓ Test completed successfully!"

rescue => e
  puts
  puts "=" * 80
  puts "ERROR OCCURRED"
  puts "=" * 80
  puts "#{e.class}: #{e.message}"
  puts
  puts "Backtrace:"
  puts e.backtrace.first(10).join("\n")
  puts "=" * 80
  exit 1
end
