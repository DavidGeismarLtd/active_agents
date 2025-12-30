module PromptTracker
  class ApplicationController < ActionController::Base
    include PromptTracker::Concerns::BasicAuthentication

    # Make DatasetsHelper available in all views
    helper DatasetsHelper
  end
end
