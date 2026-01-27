# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Evaluates whether the model properly used web search during a response.
    #
    # This evaluator checks if web search was invoked, optionally verifying
    # that specific queries were made or that results came from expected domains.
    #
    # @example Verify web search was used
    #   evaluator = WebSearchEvaluator.new(conversation_data, {
    #     require_web_search: true,
    #     min_sources: 2
    #   })
    #   evaluation = evaluator.evaluate
    #
    # @example Verify specific queries were made
    #   evaluator = WebSearchEvaluator.new(conversation_data, {
    #     expected_queries: ["Ruby on Rails", "web framework"],
    #     require_all_queries: false
    #   })
    #
    class WebSearchEvaluator < BaseNormalizedEvaluator
      # Default configuration
      DEFAULT_CONFIG = {
        require_web_search: true,       # Must use web search at least once
        expected_queries: [],            # Optional: query terms that should appear
        require_all_queries: false,      # If true, ALL query terms must be found
        expected_domains: [],            # Optional: domains that should appear in results
        require_all_domains: false,      # If true, ALL domains must be found
        min_sources_consulted: 0,        # Minimum URLs the model should research (from action.sources)
        min_sources_cited: 0,            # Minimum URLs the model should cite (from annotations)
        threshold_score: 80
      }.freeze

      # Parameter schema for form processing
      def self.param_schema
        {
          require_web_search: { type: :boolean },
          expected_queries: { type: :array },
          require_all_queries: { type: :boolean },
          expected_domains: { type: :array },
          require_all_domains: { type: :boolean },
          min_sources_consulted: { type: :integer },
          min_sources_cited: { type: :integer },
          threshold_score: { type: :integer }
        }
      end

      # Metadata for registry auto-discovery
      def self.metadata
        {
          name: "Web Search",
          description: "Verifies that the model used web search and optionally checks queries/sources",
          icon: "globe",
          default_config: DEFAULT_CONFIG,
          category: :tool_use
        }
      end

      # Initialize the evaluator
      #
      # @param data [Hash] the normalized data with web_search_results
      # @param config [Hash] configuration options
      def initialize(data, config = {})
        super(data, DEFAULT_CONFIG.merge(config.symbolize_keys))
      end

      # Calculate score based on web search usage
      #
      # @return [Float] score from 0-100
      def evaluate_score
        return 100 unless config[:require_web_search]
        return 0 if web_search_results.empty?

        score_components = []

        # Base score for using web search (40 points)
        score_components << 40

        # Score for queries matched (30 points)
        if expected_queries.any?
          query_score = calculate_query_match_score
          score_components << (query_score * 0.3)
        else
          score_components << 30
        end

        # Score for domains matched (20 points)
        if expected_domains.any?
          domain_score = calculate_domain_match_score
          score_components << (domain_score * 0.2)
        else
          score_components << 20
        end

        # Score for sources consulted (5 points)
        if config[:min_sources_consulted].to_i > 0
          consulted_score = calculate_sources_consulted_score
          score_components << (consulted_score * 0.05)
        else
          score_components << 5
        end

        # Score for sources cited (5 points)
        if config[:min_sources_cited].to_i > 0
          cited_score = calculate_sources_cited_score
          score_components << (cited_score * 0.05)
        else
          score_components << 5
        end

        score_components.sum.round(2)
      end

      # Generate feedback about web search results
      #
      # @return [String] feedback text
      def generate_feedback
        if web_search_results.empty?
          return config[:require_web_search] ? "✗ Web search was not used." : "Web search was not used (not required)."
        end

        feedback_parts = [
          "Web Search Evaluation Results:",
          "Searches performed: #{web_search_results.count}",
          "Queries: #{all_queries.any? ? all_queries.join(', ') : 'None detected'}",
          "Sources consulted: #{sources_consulted_count} (URLs researched)",
          "Sources cited: #{sources_cited_count} (URLs referenced in response)"
        ]

        if expected_queries.any?
          matched = matched_queries
          feedback_parts << "Expected queries: #{expected_queries.join(', ')}"
          feedback_parts << "Matched queries: #{matched.any? ? matched.join(', ') : 'None'}"
        end

        if expected_domains.any?
          matched = matched_domains
          feedback_parts << "Expected domains: #{expected_domains.join(', ')}"
          feedback_parts << "Matched domains: #{matched.any? ? matched.join(', ') : 'None'}"
        end

        if config[:min_sources_consulted].to_i > 0
          feedback_parts << "Min sources consulted required: #{config[:min_sources_consulted]}"
        end

        if config[:min_sources_cited].to_i > 0
          feedback_parts << "Min sources cited required: #{config[:min_sources_cited]}"
        end

        feedback_parts << (passed? ? "✓ Web search requirements met." : "✗ Some requirements not met.")
        feedback_parts.join("\n")
      end

      # Add metadata about web search details
      #
      # @return [Hash] metadata
      def metadata
        super.merge(
          "web_search_count" => web_search_results.count,
          "queries" => all_queries,
          "sources_consulted" => sources_consulted_count,
          "sources_consulted_list" => all_sources_consulted,
          "sources_cited" => sources_cited_count,
          "sources_cited_list" => all_sources_cited,
          "matched_queries" => matched_queries,
          "matched_domains" => matched_domains,
          "expected_queries" => expected_queries,
          "expected_domains" => expected_domains
        )
      end

      # Determine if evaluation passed
      #
      # @return [Boolean] true if requirements met
      def passed?
        evaluate_score >= (config[:threshold_score] || 80)
      end

      private

      # Get expected queries from config
      #
      # @return [Array<String>] expected query terms
      def expected_queries
        @expected_queries ||= Array(config[:expected_queries]).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      # Get expected domains from config
      #
      # @return [Array<String>] expected domain patterns
      def expected_domains
        @expected_domains ||= Array(config[:expected_domains]).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      # Get all queries from web search results
      #
      # @return [Array<String>] all queries made
      def all_queries
        @all_queries ||= web_search_results.filter_map { |ws| ws[:query] }.uniq
      end

      # Get all sources consulted (from action.sources)
      #
      # These are the comprehensive list of URLs the model researched.
      # Only available when API is called with include: ["web_search_call.action.sources"]
      #
      # Deduplicates by URL to prevent counting the same source multiple times
      # when multiple web_search_call items share the same source pool.
      #
      # @return [Array<Hash>] all sources consulted (deduplicated by URL)
      def all_sources_consulted
        @all_sources_consulted ||= web_search_results
          .flat_map { |ws| ws[:sources] || [] }
          .uniq { |source| source[:url] }
      end

      # Get all sources cited (from annotations)
      #
      # These are the URLs the model actually referenced in its response.
      # Always available in the response annotations.
      #
      # Deduplicates by URL to prevent counting the same citation multiple times
      # when multiple web_search_call items share the same citation pool.
      #
      # @return [Array<Hash>] all sources cited (deduplicated by URL)
      def all_sources_cited
        @all_sources_cited ||= web_search_results
          .flat_map { |ws| ws[:citations] || [] }
          .uniq { |citation| citation[:url] }
      end

      # Get count of sources consulted (from action.sources)
      #
      # @return [Integer] number of sources consulted
      def sources_consulted_count
        @sources_consulted_count ||= all_sources_consulted.length
      end

      # Get count of sources cited (from annotations)
      #
      # @return [Integer] number of sources cited
      def sources_cited_count
        @sources_cited_count ||= all_sources_cited.length
      end

      # Get all sources (hybrid fallback for backward compatibility)
      #
      # Prefer sources consulted, fall back to sources cited.
      # This maintains backward compatibility with existing code.
      #
      # @return [Array<Hash>] all sources
      def all_sources
        @all_sources ||= all_sources_consulted.any? ? all_sources_consulted : all_sources_cited
      end

      # Find which expected queries were matched
      #
      # @return [Array<String>] matched query terms
      def matched_queries
        @matched_queries ||= expected_queries.select do |expected|
          all_queries.any? { |query| query_matches?(query, expected) }
        end
      end

      # Find which expected domains were found in sources
      #
      # Checks both sources consulted and sources cited
      #
      # @return [Array<String>] matched domains
      def matched_domains
        @matched_domains ||= begin
          # Combine domains from both consulted and cited sources
          consulted_domains = all_sources_consulted.filter_map { |s| extract_domain(s[:url]) }
          cited_domains = all_sources_cited.filter_map { |s| extract_domain(s[:url]) }
          all_domains = (consulted_domains + cited_domains).uniq

          expected_domains.select do |expected|
            all_domains.any? { |domain| domain_matches?(domain, expected) }
          end
        end
      end

      # Check if a query matches an expected term
      #
      # @param query [String] the actual query
      # @param expected [String] the expected query term
      # @return [Boolean] true if match
      def query_matches?(query, expected)
        return false if query.nil? || expected.nil?

        query.downcase.include?(expected.downcase)
      end

      # Check if a domain matches an expected pattern
      #
      # @param domain [String] the actual domain
      # @param expected [String] the expected domain pattern
      # @return [Boolean] true if match
      def domain_matches?(domain, expected)
        return false if domain.nil? || expected.nil?

        domain.downcase.include?(expected.downcase)
      end

      # Extract domain from URL
      #
      # @param url [String] the URL
      # @return [String, nil] the domain
      def extract_domain(url)
        return nil if url.nil?

        URI.parse(url).host
      rescue URI::InvalidURIError
        nil
      end

      # Calculate score for query matching
      #
      # @return [Float] score 0-100
      def calculate_query_match_score
        return 100 if expected_queries.empty?

        matched_count = matched_queries.count
        total_count = expected_queries.count

        if config[:require_all_queries]
          matched_count == total_count ? 100 : (matched_count.to_f / total_count * 100)
        else
          matched_count > 0 ? 100 : 0
        end
      end

      # Calculate score for domain matching
      #
      # @return [Float] score 0-100
      def calculate_domain_match_score
        return 100 if expected_domains.empty?

        matched_count = matched_domains.count
        total_count = expected_domains.count

        if config[:require_all_domains]
          matched_count == total_count ? 100 : (matched_count.to_f / total_count * 100)
        else
          matched_count > 0 ? 100 : 0
        end
      end

      # Calculate score for minimum sources consulted requirement
      #
      # @return [Float] score 0-100
      def calculate_sources_consulted_score
        min_required = config[:min_sources_consulted].to_i
        return 100 if min_required <= 0

        actual = sources_consulted_count
        actual >= min_required ? 100 : (actual.to_f / min_required * 100)
      end

      # Calculate score for minimum sources cited requirement
      #
      # @return [Float] score 0-100
      def calculate_sources_cited_score
        min_required = config[:min_sources_cited].to_i
        return 100 if min_required <= 0

        actual = sources_cited_count
        actual >= min_required ? 100 : (actual.to_f / min_required * 100)
      end
    end
  end
end
