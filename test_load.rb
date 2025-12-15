#!/usr/bin/env ruby

puts "Step 1: Loading bundler..."
require "bundler/setup"

puts "Step 2: Loading Rails..."
require "rails"

puts "Step 3: Loading PromptTracker version..."
require_relative "lib/prompt_tracker/version"
puts "Version: #{PromptTracker::VERSION}"

puts "Step 4: Loading PromptTracker engine..."
require_relative "lib/prompt_tracker/engine"

puts "Step 5: Loading PromptTracker configuration..."
require_relative "lib/prompt_tracker/configuration"

puts "Step 6: All loaded successfully!"
puts "Configuration class: #{PromptTracker::Configuration}"
