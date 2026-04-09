# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    # Lightweight, tool-free "docs awareness" for the assistant.
    #
    # We extract plain-ish text from the docs ERB views and provide
    # a small set of relevant excerpts for the user's query.
    class DocsKnowledgeBase
      DOCS_DIR = PromptTracker::Engine.root.join("app/views/prompt_tracker/docs")

      DOCS = {
        tracking: {
          file: "tracking.html.erb",
          route_suffix: "docs/tracking"
        },
        playground_guide: {
          file: "playground_guide.html.erb",
          route_suffix: "docs/playground_guide"
        },
        testing_guide: {
          file: "testing_guide.html.erb",
          route_suffix: "docs/testing_guide"
        }
      }.freeze

      Document = Struct.new(:key, :route, :text, keyword_init: true)

      # Get the engine's mounted base path dynamically.
      # @return [String] base path without trailing slash
      def self.engine_base_path
        url_options = PromptTracker.configuration.url_options_provider&.call || {}
        PromptTracker::Engine.routes.url_helpers.root_path(url_options).chomp("/")
      end

      # Build a full route from a doc's route_suffix.
      # @param route_suffix [String] e.g. "docs/tracking"
      # @return [String] e.g. "/prompt_tracker/docs/tracking"
      def self.doc_route(route_suffix)
        "#{engine_base_path}/#{route_suffix}"
      end

      def self.context_for(query, max_docs: 2, excerpt_chars: 900)
          query_preview = query.to_s[0, 200]
          Rails.logger.info("[DocsKnowledgeBase] search start query_preview=#{query_preview.inspect} max_docs=#{max_docs} excerpt_chars=#{excerpt_chars}")
          Rails.logger.info("[DocsKnowledgeBase] docs_dir=#{DOCS_DIR}")
          Rails.logger.info("[DocsKnowledgeBase] docs=#{DOCS.map { |k, v| "#{k}:#{doc_route(v[:route_suffix])}" }.join(", ")}")

        docs_list = DOCS.map { |key, meta| "- #{doc_route(meta[:route_suffix])} (#{key})" }.join("\n")

        query_terms = tokenize(query)
          Rails.logger.info("[DocsKnowledgeBase] query_terms_count=#{query_terms.length} query_terms_sample=#{query_terms.first(25).inspect}")

        ranked = documents
          .map { |doc| [ score(doc.text, query_terms), doc ] }
          .sort_by { |(s, _)| -s }

          Rails.logger.info("[DocsKnowledgeBase] scores=#{ranked.map { |(s, d)| { key: d.key, score: s, route: d.route, text_chars: d.text.length } }.inspect}")

        chosen = ranked.select { |(s, _)| s.positive? }.first(max_docs).map(&:last)
          Rails.logger.info("[DocsKnowledgeBase] chosen=#{chosen.map(&:key).inspect}")

        header = <<~TXT.strip
          PromptTracker documentation pages available:
          #{docs_list}
        TXT

          if chosen.empty?
            Rails.logger.info("[DocsKnowledgeBase] no matches - returning routes-only context")
            return header
          end

        excerpts = chosen.map { |doc| format_excerpt(doc, query_terms, excerpt_chars) }.join("\n\n")

        <<~TXT.strip
          #{header}

          Relevant excerpts (use these to answer):
          #{excerpts}
        TXT
      end

      def self.reset!
        @documents = nil
      end

      def self.documents
          Rails.logger.info("[DocsKnowledgeBase] loading documents") unless defined?(@documents) && @documents
        @documents ||= DOCS.map do |key, meta|
          path = DOCS_DIR.join(meta[:file])
            Rails.logger.info("[DocsKnowledgeBase] reading #{path}")
          raw = File.read(path)
          Document.new(key: key, route: doc_route(meta[:route_suffix]), text: strip_view_markup(raw))
        end
      end

      def self.strip_view_markup(raw)
        raw
          .gsub(/<%[\s\S]*?%>/, " ")
          .gsub(/<[^>]+>/, " ")
          .gsub(/\s+/, " ")
          .strip
      end

      def self.tokenize(text)
        text.to_s.downcase.scan(/[a-z0-9_]+/).uniq
      end

      def self.score(doc_text, query_terms)
        haystack = doc_text.to_s.downcase
        query_terms.sum { |t| haystack.scan(t).length }
      end

      def self.format_excerpt(doc, query_terms, excerpt_chars)
        down = doc.text.downcase
        match_index = query_terms.filter_map { |t| down.index(t) }.min

        start_index = match_index ? [ match_index - (excerpt_chars / 3), 0 ].max : 0
        excerpt = doc.text[start_index, excerpt_chars] || ""
          Rails.logger.info("[DocsKnowledgeBase] excerpt doc=#{doc.key} match_index=#{match_index.inspect} start_index=#{start_index} excerpt_chars=#{excerpt.length}")

        <<~TXT.strip
          [#{doc.key}] #{doc.route}
          #{excerpt}
        TXT
      end

      private_class_method :engine_base_path, :doc_route, :strip_view_markup, :tokenize, :score, :format_excerpt
    end
  end
end
