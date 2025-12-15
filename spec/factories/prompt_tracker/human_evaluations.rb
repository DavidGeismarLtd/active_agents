# frozen_string_literal: true

FactoryBot.define do
  factory :human_evaluation, class: "PromptTracker::HumanEvaluation" do
    association :evaluation, factory: :evaluation
    score { rand(0..100) }
    feedback { "This automated evaluation was #{score >= 70 ? 'accurate' : 'not quite right'}. #{Faker::Lorem.sentence}" }

    trait :high_score do
      score { rand(80..100) }
      feedback { "Excellent automated evaluation. #{Faker::Lorem.sentence}" }
    end

    trait :low_score do
      score { rand(0..50) }
      feedback { "The automated evaluation missed some important aspects. #{Faker::Lorem.sentence}" }
    end

    trait :agrees_with_evaluation do
      score { evaluation.score + rand(-5..5) }
      feedback { "The automated evaluation was mostly correct. #{Faker::Lorem.sentence}" }
    end

    trait :disagrees_with_evaluation do
      score { evaluation.score + (evaluation.score >= 50 ? -30 : 30) }
      feedback { "I disagree with the automated evaluation. #{Faker::Lorem.sentence}" }
    end
  end
end
