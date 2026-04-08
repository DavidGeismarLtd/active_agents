module PromptTracker
  class ApplicationRecord < PromptTracker.configuration.base_record_class.constantize
    self.abstract_class = true
    acts_as_tenant :organization
  end
end
