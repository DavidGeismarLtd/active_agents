# frozen_string_literal: true

module PromptTracker
  # Provides Kaminari-compatible pagination that works even when the host app
  # uses will_paginate. will_paginate overrides ActiveRecord::Relation#page,
  # which breaks Kaminari's .page().per() chain on scoped queries and associations.
  #
  # Usage in controllers:
  #   @rows = PromptTracker::DatasetRow.pt_paginate(@dataset.dataset_rows.recent, page: params[:page], per_page: 50)
  #   # or shorter with the helper:
  #   @rows = pt_paginate(@dataset.dataset_rows.recent, page: params[:page], per_page: 50)
  module KaminariPagination
    extend ActiveSupport::Concern

    class_methods do
      # Paginates any scope or association using Kaminari, bypassing will_paginate.
      #
      # @param scope [ActiveRecord::Relation, CollectionProxy] the scope to paginate
      # @param page [Integer, String, nil] page number (defaults to 1)
      # @param per_page [Integer] items per page (defaults to 25)
      # @return [Kaminari::PaginatableArray] paginated result with total_pages, current_page, etc.
      def pt_paginate(scope, page: nil, per_page: 25)
        page = (page || 1).to_i
        per_page = per_page.to_i
        total = scope.count(:all)
        records = scope.limit(per_page).offset((page - 1) * per_page).to_a

        Kaminari.paginate_array(records, total_count: total).page(page).per(per_page)
      end
    end
  end
end
