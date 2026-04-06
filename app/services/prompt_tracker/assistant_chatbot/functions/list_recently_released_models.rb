# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Functions
      # Read-only helper that lists recently released models.
      #
      # Intended for the Agent Creation wizard so it can offer a short,
      # sensible list of model options derived from provider model IDs.
      #
      # Arguments:
      # - per_provider_limit: (optional) number of models to include per provider (default: 5, max: 10)
      #
      # Returns:
      # - Human-readable list with the configured default model first
      class ListRecentlyReleasedModels < Base
          DEFAULT_PER_PROVIDER_LIMIT = 5
          MAX_PER_PROVIDER_LIMIT = 10

        protected

          def execute
            per_provider_limit = (arg(:per_provider_limit) || DEFAULT_PER_PROVIDER_LIMIT).to_i.clamp(1, MAX_PER_PROVIDER_LIMIT)

          defaults = playground_defaults
          default_model_id = defaults[:model]

            models_by_provider = enabled_providers.index_with do |provider|
              PromptTracker::RubyLlmModelAdapter.raw_models_for(provider).map { |m| m.merge(provider: provider) }
            end

            options = build_options(models_by_provider, default_model_id, per_provider_limit)

            success(format_message(default_model_id, options, per_provider_limit))
        end

        private

        def playground_defaults
          {
            provider: (PromptTracker.configuration.default_provider_for(:playground) || :openai),
            api: (PromptTracker.configuration.default_api_for(:playground) || :chat_completions),
            model: (PromptTracker.configuration.default_model_for(:playground) || "gpt-4o")
          }
        end

        def enabled_providers
          PromptTracker.configuration.enabled_providers
        end

          def build_options(models_by_provider, default_model_id, per_provider_limit)
            all_models = models_by_provider.values.flatten

            default_entry = all_models.find { |m| m[:id] == default_model_id } || {
            id: default_model_id,
            name: default_model_id,
            provider: playground_defaults[:provider]
          }

            recent_by_provider = models_by_provider.transform_values do |provider_models|
              provider_models
                .map { |m| m.merge(release_date: release_date_for(m[:id])) }
                .select { |m| m[:release_date].present? && m[:id] != default_model_id }
                .sort_by { |m| m[:release_date] }
                .reverse
                .first(per_provider_limit)
            end

            [ default_entry.merge(release_date: release_date_for(default_entry[:id])), recent_by_provider ]
        end

        def release_date_for(model_id)
          id = model_id.to_s

          if (m = id.match(/-(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})\z/))
            Date.new(m[:year].to_i, m[:month].to_i, m[:day].to_i)
          elsif (m = id.match(/-(?<date>\d{8})\z/))
            Date.strptime(m[:date], "%Y%m%d")
          end
        rescue ArgumentError
          nil
        end

          def format_message(default_model_id, options, per_provider_limit)
            default_entry, recent_by_provider = options

            lines = []
            lines << format_line(1, default_entry, default_model_id)

            idx = 2
            recent_by_provider.each do |provider, provider_models|
              lines << "\n#{provider.to_s.capitalize} (latest #{per_provider_limit}):"

              provider_models.each do |m|
                lines << format_line(idx, m, default_model_id)
                idx += 1
              end
            end

            <<~MSG.strip
	            Here are recent model options per enabled provider (default first):

	            #{lines.join("\n")}

	            Reply with the model ID you want, or say "default" to use the first option.
            MSG
          end

          def format_line(idx, model, default_model_id)
            provider = model[:provider].to_s
            name = model[:name] || model[:id]
            date = model[:release_date]&.iso8601
            date_suffix = date ? " — released #{date}" : ""
            default_suffix = (idx == 1 && model[:id] == default_model_id) ? " (default)" : ""
            "#{idx}. #{name} (#{model[:id]}) [#{provider}]#{default_suffix}#{date_suffix}"
          end
      end
    end
  end
end
