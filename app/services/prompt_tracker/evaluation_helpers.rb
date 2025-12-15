# frozen_string_literal: true

module PromptTracker
  # Helper methods for working with evaluations.
  #
  # Provides utilities for:
  # - Normalizing scores across different scales
  # - Aggregating scores from multiple evaluations
  # - Calculating statistics
  #
  # @example Normalize a score
  #   normalized = EvaluationHelpers.normalize_score(85, min: 0, max: 100, target_max: 5)
  #   # => 4.25
  #
  # @example Calculate average score for a prompt version
  #   avg = EvaluationHelpers.average_score_for_version(prompt_version)
  #   # => 4.2
  #
  module EvaluationHelpers
    # Normalize a score from one scale to another
    #
    # @param score [Numeric] the score to normalize
    # @param min [Numeric] minimum value of the original scale
    # @param max [Numeric] maximum value of the original scale
    # @param target_min [Numeric] minimum value of the target scale (default: 0)
    # @param target_max [Numeric] maximum value of the target scale (default: 1)
    # @return [Float] the normalized score
    #
    # @example Normalize 0-100 scale to 0-5 scale
    #   normalize_score(85, min: 0, max: 100, target_max: 5)
    #   # => 4.25
    #
    # @example Normalize to 0-1 scale (percentage)
    #   normalize_score(4.5, min: 0, max: 5, target_max: 1)
    #   # => 0.9
    def self.normalize_score(score, min:, max:, target_min: 0, target_max: 1)
      return target_min if score <= min
      return target_max if score >= max

      # Linear interpolation
      range = max - min
      target_range = target_max - target_min
      normalized = ((score - min).to_f / range) * target_range + target_min

      normalized.round(2)
    end

    # Calculate the average score for a prompt version
    #
    # Normalizes all scores to 0-1 scale before averaging
    #
    # @param prompt_version [PromptVersion] the prompt version
    # @param evaluator_type [String, nil] optional filter by evaluator type
    # @return [Float, nil] average normalized score, or nil if no evaluations
    #
    # @example Get average score for all evaluations
    #   average_score_for_version(version)
    #   # => 0.85
    #
    # @example Get average score for human evaluations only
    #   average_score_for_version(version, evaluator_type: "human")
    #   # => 0.92
    def self.average_score_for_version(prompt_version, evaluator_type: nil)
      evaluations = prompt_version.evaluations
      evaluations = evaluations.where(evaluator_type: evaluator_type) if evaluator_type

      return nil if evaluations.empty?

      normalized_scores = evaluations.map do |eval|
        normalize_score(eval.score, min: eval.score_min, max: eval.score_max)
      end

      (normalized_scores.sum / normalized_scores.length.to_f).round(3)
    end

    # Calculate the average score for an LLM response
    #
    # @param llm_response [LlmResponse] the LLM response
    # @param evaluator_type [String, nil] optional filter by evaluator type
    # @return [Float, nil] average normalized score, or nil if no evaluations
    def self.average_score_for_response(llm_response, evaluator_type: nil)
      evaluations = llm_response.evaluations
      evaluations = evaluations.where(evaluator_type: evaluator_type) if evaluator_type

      return nil if evaluations.empty?

      normalized_scores = evaluations.map do |eval|
        normalize_score(eval.score, min: eval.score_min, max: eval.score_max)
      end

      (normalized_scores.sum / normalized_scores.length.to_f).round(3)
    end

    # Calculate statistics for evaluations
    #
    # @param evaluations [ActiveRecord::Relation<Evaluation>] the evaluations
    # @return [Hash] statistics hash with min, max, avg, median, count
    #
    # @example
    #   stats = evaluation_statistics(prompt_version.evaluations)
    #   # => {
    #   #   count: 10,
    #   #   min: 0.6,
    #   #   max: 1.0,
    #   #   avg: 0.85,
    #   #   median: 0.87
    #   # }
    def self.evaluation_statistics(evaluations)
      return nil if evaluations.empty?

      normalized_scores = evaluations.map do |eval|
        normalize_score(eval.score, min: eval.score_min, max: eval.score_max)
      end

      sorted = normalized_scores.sort
      count = sorted.length

      {
        count: count,
        min: sorted.first.round(3),
        max: sorted.last.round(3),
        avg: (sorted.sum / count.to_f).round(3),
        median: calculate_median(sorted).round(3)
      }
    end

    # Compare scores across multiple prompt versions
    #
    # @param prompt_versions [Array<PromptVersion>] versions to compare
    # @param evaluator_type [String, nil] optional filter by evaluator type
    # @return [Hash] hash of version_number => average_score
    #
    # @example
    #   compare_versions([version1, version2, version3])
    #   # => { 1 => 0.75, 2 => 0.85, 3 => 0.92 }
    def self.compare_versions(prompt_versions, evaluator_type: nil)
      prompt_versions.each_with_object({}) do |version, hash|
        avg = average_score_for_version(version, evaluator_type: evaluator_type)
        hash[version.version_number] = avg if avg
      end
    end

    # Get the best performing version based on average score
    #
    # @param prompt_versions [Array<PromptVersion>] versions to compare
    # @param evaluator_type [String, nil] optional filter by evaluator type
    # @return [PromptVersion, nil] the best version, or nil if no evaluations
    #
    # @example
    #   best = best_version(prompt.prompt_versions)
    #   # => #<PromptVersion version_number: 3>
    def self.best_version(prompt_versions, evaluator_type: nil)
      scores = compare_versions(prompt_versions, evaluator_type: evaluator_type)
      return nil if scores.empty?

      best_version_number = scores.max_by { |_version, score| score }&.first
      prompt_versions.find { |v| v.version_number == best_version_number }
    end

    # Aggregate criteria scores across multiple evaluations
    #
    # @param evaluations [ActiveRecord::Relation<Evaluation>] the evaluations
    # @return [Hash] hash of criterion => average_score
    #
    # @example
    #   aggregate_criteria_scores(evaluations)
    #   # => {
    #   #   "accuracy" => 4.5,
    #   #   "helpfulness" => 4.2,
    #   #   "tone" => 4.8
    #   # }
    def self.aggregate_criteria_scores(evaluations)
      return {} if evaluations.empty?

      # Collect all criteria across all evaluations
      all_criteria = evaluations.flat_map { |e| e.criteria_scores.keys }.uniq

      all_criteria.each_with_object({}) do |criterion, hash|
        scores = evaluations.filter_map do |eval|
          eval.criteria_scores[criterion] if eval.criteria_scores.key?(criterion)
        end

        next if scores.empty?

        hash[criterion] = (scores.sum / scores.length.to_f).round(2)
      end
    end

    # Calculate score distribution
    #
    # @param evaluations [ActiveRecord::Relation<Evaluation>] the evaluations
    # @param buckets [Integer] number of buckets for distribution (default: 5)
    # @return [Hash] hash of bucket_range => count
    #
    # @example
    #   score_distribution(evaluations, buckets: 5)
    #   # => {
    #   #   "0.0-0.2" => 2,
    #   #   "0.2-0.4" => 5,
    #   #   "0.4-0.6" => 10,
    #   #   "0.6-0.8" => 15,
    #   #   "0.8-1.0" => 8
    #   # }
    def self.score_distribution(evaluations, buckets: 5)
      return {} if evaluations.empty?

      normalized_scores = evaluations.map do |eval|
        normalize_score(eval.score, min: eval.score_min, max: eval.score_max)
      end

      bucket_size = 1.0 / buckets
      distribution = Hash.new(0)

      normalized_scores.each do |score|
        bucket_index = [ (score / bucket_size).floor, buckets - 1 ].min
        bucket_min = (bucket_index * bucket_size).round(1)
        bucket_max = ((bucket_index + 1) * bucket_size).round(1)
        bucket_key = "#{bucket_min}-#{bucket_max}"

        distribution[bucket_key] += 1
      end

      distribution
    end

    # Private helper to calculate median
    #
    # @param sorted_array [Array<Numeric>] sorted array of numbers
    # @return [Float] the median value
    def self.calculate_median(sorted_array)
      length = sorted_array.length
      mid = length / 2

      if length.odd?
        sorted_array[mid]
      else
        (sorted_array[mid - 1] + sorted_array[mid]) / 2.0
      end
    end

    private_class_method :calculate_median
  end
end
