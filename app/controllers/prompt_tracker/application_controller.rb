module PromptTracker
  class ApplicationController < ActionController::Base
    include PromptTracker::Concerns::BasicAuthentication

    # Make helpers available in all views (including background job rendering)
    helper UrlHelper
    helper DatasetsHelper
    helper TestsHelper

    # Override default_url_options to support multi-tenant mounting.
    # When the engine is mounted under a scoped route like /orgs/:org_slug/app,
    # the url_options_provider configuration allows the host app to provide
    # the required URL parameters dynamically.
    #
    # @return [Hash] URL options to be merged into all URL generation
    def default_url_options
      base_options = super

      if PromptTracker.configuration.url_options_provider
        base_options.merge(PromptTracker.configuration.url_options_provider.call || {})
      else
        base_options
      end
    end
  end
end
