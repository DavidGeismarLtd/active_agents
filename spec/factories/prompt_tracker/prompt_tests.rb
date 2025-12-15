# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_prompt_tests
#
#  created_at         :datetime         not null
#  description        :text
#  enabled            :boolean          default(TRUE), not null
#  id                 :bigint           not null, primary key
#  metadata           :jsonb            not null
#  model_config       :jsonb            not null
#  name               :string           not null
#  prompt_version_id  :bigint           not null
#  tags               :jsonb            not null
#  updated_at         :datetime         not null
#
FactoryBot.define do
  factory :prompt_test, class: "PromptTracker::PromptTest" do
    association :prompt_version, factory: :prompt_version

    sequence(:name) { |n| "test_#{n}" }
    description { "Test description" }
    model_config { { provider: "openai", model: "gpt-4", temperature: 0.7 } }
    enabled { true }
    metadata { {} }
  end
end
