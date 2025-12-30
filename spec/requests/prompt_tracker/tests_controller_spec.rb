# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PromptTracker::TestsController", type: :request do
  let(:prompt) { create(:prompt) }
  let(:version) { create(:prompt_version, prompt: prompt, status: "active") }
  let(:test) { create(:test, testable: version) }
end
