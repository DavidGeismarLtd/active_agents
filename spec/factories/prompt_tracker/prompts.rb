# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_prompts
#
#  archived_at :datetime
#  category    :string
#  created_at  :datetime         not null
#  created_by  :string
#  description :text
#  id          :bigint           not null, primary key
#  name        :string           not null
#  slug        :string           not null
#  tags        :jsonb
#  updated_at  :datetime         not null
#
FactoryBot.define do
  factory :prompt, class: "PromptTracker::Prompt" do
    sequence(:name) { |n| "Test Prompt #{n}" }
    sequence(:slug) { |n| "test_prompt_#{n}" }
    description { "A test prompt for #{name}" }
    created_by { "test@example.com" }
    archived_at { nil }

    trait :archived do
      archived_at { 1.day.ago }
    end

    trait :with_versions do
      after(:create) do |prompt|
        create_list(:prompt_version, 3, prompt: prompt)
      end
    end

    trait :with_active_version do
      after(:create) do |prompt|
        create(:prompt_version, :active, prompt: prompt)
      end
    end
  end
end
