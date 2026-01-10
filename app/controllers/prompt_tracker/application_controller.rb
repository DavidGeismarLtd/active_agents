module PromptTracker
  class ApplicationController < ActionController::Base
    include PromptTracker::Concerns::BasicAuthentication

    # Make helpers available in all views (including background job rendering)
    helper DatasetsHelper
    helper TestsHelper
  end
end
