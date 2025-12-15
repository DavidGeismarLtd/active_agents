#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick script to test if factories are loading correctly
require_relative 'spec/rails_helper'

puts "Testing FactoryBot factory loading..."
puts "=" * 50

# Check factory paths
puts "\nFactory definition paths:"
FactoryBot.definition_file_paths.each do |path|
  puts "  - #{path}"
  puts "    Exists: #{File.directory?(path)}"
  if File.directory?(path)
    puts "    Files:"
    Dir.glob("#{path}/**/*.rb").each do |file|
      puts "      - #{file}"
    end
  end
end

puts "\nLoading factories..."
FactoryBot.reload

puts "\nRegistered factories:"
FactoryBot.factories.each do |factory|
  puts "  - #{factory.name} (#{factory.build_class})"
end

puts "\nTrying to create a prompt..."
begin
  prompt = FactoryBot.create(:prompt)
  puts "✅ SUCCESS: Created prompt with name '#{prompt.name}'"
rescue => e
  puts "❌ ERROR: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
end

puts "\n" + "=" * 50
puts "Test complete!"
