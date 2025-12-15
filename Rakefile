require "bundler/setup"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

load "rails/tasks/statistics.rake"

require "bundler/gem_tasks"

# Load RSpec tasks
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

# Make spec the default task
task default: :spec
