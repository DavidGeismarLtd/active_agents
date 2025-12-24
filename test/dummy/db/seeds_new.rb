# frozen_string_literal: true

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "🌱 Seeding PromptTracker database..."

# Load all seed files in order
seed_files = Dir[Rails.root.join("db/seeds/*.rb")].sort

if seed_files.empty?
  puts "⚠️  No seed files found in db/seeds/"
  puts "   Expected files like: 01_cleanup.rb, 02_prompts_customer_support.rb, etc."
  exit 1
end

seed_files.each do |file|
  filename = File.basename(file)
  puts "\n📄 Loading #{filename}..."
  load file
end
