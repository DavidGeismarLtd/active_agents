module PromptTracker
  class ApplicationRecord < PromptTracker.configuration.base_record_class.constantize
    self.abstract_class = true
  end
end
