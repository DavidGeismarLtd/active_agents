# frozen_string_literal: true

module PromptTracker
  # Service for analyzing A/B test results and determining statistical significance.
  #
  # This service performs statistical analysis on A/B test data to:
  # - Calculate metrics for each variant
  # - Determine statistical significance
  # - Identify the winning variant
  # - Provide confidence intervals
  #
  # Supports both continuous metrics (response_time, cost, token_count) and
  # categorical metrics (success_rate, evaluation_score).
  #
  # @example Basic usage
  #   analyzer = AbTestAnalyzer.new(ab_test)
  #   results = analyzer.analyze
  #   # => {
  #   #   variants: {
  #   #     "A" => { mean: 1.5, std_dev: 0.3, count: 100 },
  #   #     "B" => { mean: 1.2, std_dev: 0.25, count: 105 }
  #   #   },
  #   #   winner: "B",
  #   #   p_value: 0.001,
  #   #   confidence: 0.999,
  #   #   improvement: 20.0,
  #   #   significant: true
  #   # }
  #
  # @example Check if test is ready
  #   analyzer = AbTestAnalyzer.new(ab_test)
  #   analyzer.ready_for_analysis?  # => true/false
  #   analyzer.sample_size_met?     # => true/false
  #
  class AbTestAnalyzer
    attr_reader :ab_test

    # Initialize analyzer with an A/B test
    #
    # @param ab_test [AbTest] the A/B test to analyze
    def initialize(ab_test)
      @ab_test = ab_test
    end

    # Analyze the A/B test results
    #
    # @return [Hash] analysis results with variant stats, winner, p-value, etc.
    def analyze
      return nil unless ready_for_analysis?

      variant_stats = calculate_variant_stats
      comparison = compare_variants(variant_stats)

      {
        variants: variant_stats,
        winner: comparison[:winner],
        p_value: comparison[:p_value],
        confidence: comparison[:confidence],
        improvement: comparison[:improvement],
        significant: comparison[:significant],
        sample_size_met: sample_size_met?,
        analyzed_at: Time.current
      }
    end

    # Check if test has enough data for analysis
    #
    # @return [Boolean] true if ready
    def ready_for_analysis?
      ab_test.running? && ab_test.total_responses >= 10
    end

    # Check if minimum sample size is met
    #
    # @return [Boolean] true if met
    def sample_size_met?
      return false unless ab_test.minimum_sample_size

      ab_test.total_responses >= ab_test.minimum_sample_size
    end

    # Get the current leader (best performing variant)
    #
    # @return [String, nil] variant name of current leader
    def current_leader
      variant_stats = calculate_variant_stats
      return nil if variant_stats.empty?

      # Sort by metric (considering optimization direction)
      sorted = variant_stats.sort_by do |_name, stats|
        value = stats[:mean] || 0
        ab_test.optimization_direction == "maximize" ? -value : value
      end

      sorted.first[0]
    end

    private

    # Calculate statistics for each variant
    #
    # @return [Hash] variant name => stats hash
    def calculate_variant_stats
      stats = {}

      ab_test.variant_names.each do |variant_name|
        responses = ab_test.llm_responses.where(ab_variant: variant_name)
        next if responses.empty?

        values = extract_metric_values(responses)
        next if values.empty?

        stats[variant_name] = {
          count: values.size,
          mean: calculate_mean(values),
          std_dev: calculate_std_dev(values),
          min: values.min,
          max: values.max,
          median: calculate_median(values)
        }
      end

      stats
    end

    # Extract metric values from responses
    #
    # @param responses [ActiveRecord::Relation] LlmResponse records
    # @return [Array<Numeric>] metric values
    def extract_metric_values(responses)
      metric = ab_test.metric_to_optimize
      values = []

      responses.find_each do |response|
        value = case metric
        when "response_time"
                  response.response_time_ms
        when "cost"
                  response.cost_usd
        when "token_count"
                  response.tokens_total
        when "success_rate"
                  response.status == "success" ? 1.0 : 0.0
        when "quality_score", "evaluation_score"
                  # Get average evaluation score
                  avg_score = response.evaluations.average(:score)
                  avg_score&.to_f
        else
                  nil
        end

        values << value if value.present?
      end

      values.compact
    end

    # Compare variants and determine winner
    #
    # @param variant_stats [Hash] statistics for each variant
    # @return [Hash] comparison results
    def compare_variants(variant_stats)
      return default_comparison if variant_stats.size < 2

      # Get the two main variants (assumes 2-variant test for now)
      variants = variant_stats.keys.sort
      variant_a = variants[0]
      variant_b = variants[1]

      stats_a = variant_stats[variant_a]
      stats_b = variant_stats[variant_b]

      # Perform t-test
      t_stat, p_value = perform_t_test(stats_a, stats_b)

      # Determine winner based on optimization direction
      winner = determine_winner(stats_a, stats_b, variant_a, variant_b)

      # Calculate improvement percentage
      improvement = calculate_improvement(stats_a, stats_b, winner, variant_a)

      # Check significance
      significant = p_value < (1.0 - ab_test.confidence_level)

      {
        winner: winner,
        p_value: p_value,
        confidence: 1.0 - p_value,
        improvement: improvement,
        significant: significant,
        t_statistic: t_stat
      }
    end

    # Perform Welch's t-test
    #
    # @param stats_a [Hash] statistics for variant A
    # @param stats_b [Hash] statistics for variant B
    # @return [Array<Float>] t-statistic and p-value
    def perform_t_test(stats_a, stats_b)
      mean_a = stats_a[:mean]
      mean_b = stats_b[:mean]
      var_a = stats_a[:std_dev]**2
      var_b = stats_b[:std_dev]**2
      n_a = stats_a[:count]
      n_b = stats_b[:count]

      # Welch's t-statistic
      t_stat = (mean_a - mean_b) / Math.sqrt((var_a / n_a) + (var_b / n_b))

      # Degrees of freedom (Welch-Satterthwaite equation)
      df = ((var_a / n_a) + (var_b / n_b))**2 /
           ((var_a / n_a)**2 / (n_a - 1) + (var_b / n_b)**2 / (n_b - 1))

      # Approximate p-value using t-distribution
      # For simplicity, using a rough approximation
      # In production, you'd use a proper statistical library
      p_value = approximate_p_value(t_stat.abs, df)

      [ t_stat, p_value ]
    end

    # Approximate p-value from t-statistic
    #
    # This is a simplified approximation. For production use,
    # consider using a statistical library like 'statistics2' gem.
    #
    # @param t [Float] t-statistic (absolute value)
    # @param df [Float] degrees of freedom
    # @return [Float] approximate p-value
    def approximate_p_value(t, df)
      # Very rough approximation using normal distribution for large df
      # For df > 30, t-distribution ≈ normal distribution
      if df > 30
        # Using standard normal approximation
        # P(|Z| > t) ≈ 2 * (1 - Φ(t))
        # Φ(t) ≈ 0.5 * (1 + erf(t / sqrt(2)))
        z = t
        phi = 0.5 * (1.0 + Math.erf(z / Math.sqrt(2)))
        p_value = 2.0 * (1.0 - phi)
        [ p_value, 0.001 ].max # Minimum p-value
      else
        # For small df, use conservative estimate
        0.05
      end
    end

    # Determine winner based on means and optimization direction
    #
    # @param stats_a [Hash] statistics for variant A
    # @param stats_b [Hash] statistics for variant B
    # @param variant_a [String] name of variant A
    # @param variant_b [String] name of variant B
    # @return [String] winner variant name
    def determine_winner(stats_a, stats_b, variant_a, variant_b)
      if ab_test.optimization_direction == "maximize"
        stats_a[:mean] > stats_b[:mean] ? variant_a : variant_b
      else
        stats_a[:mean] < stats_b[:mean] ? variant_a : variant_b
      end
    end

    # Calculate improvement percentage
    #
    # @param stats_a [Hash] statistics for variant A
    # @param stats_b [Hash] statistics for variant B
    # @param winner [String] winner variant name
    # @param variant_a [String] name of variant A
    # @return [Float] improvement percentage
    def calculate_improvement(stats_a, stats_b, winner, variant_a)
      baseline = winner == variant_a ? stats_b[:mean] : stats_a[:mean]
      winner_mean = winner == variant_a ? stats_a[:mean] : stats_b[:mean]

      return 0.0 if baseline.zero?

      ((winner_mean - baseline) / baseline.abs * 100.0).abs.round(2)
    end

    # Default comparison when not enough data
    #
    # @return [Hash] default comparison results
    def default_comparison
      {
        winner: nil,
        p_value: 1.0,
        confidence: 0.0,
        improvement: 0.0,
        significant: false
      }
    end

    # Calculate mean
    def calculate_mean(values)
      return 0.0 if values.empty?
      values.sum.to_f / values.size
    end

    # Calculate standard deviation
    def calculate_std_dev(values)
      return 0.0 if values.size < 2
      mean = calculate_mean(values)
      variance = values.map { |v| (v - mean)**2 }.sum / (values.size - 1)
      Math.sqrt(variance)
    end

    # Calculate median
    def calculate_median(values)
      return 0.0 if values.empty?
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end
  end
end
