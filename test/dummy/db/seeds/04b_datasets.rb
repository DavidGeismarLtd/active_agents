# frozen_string_literal: true

# ============================================================================
# Datasets for PromptVersions
# ============================================================================

puts "  Creating datasets for prompt versions..."

# ============================================================================
# 1. Customer Support Greeting Dataset
# ============================================================================

support_greeting_v3 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "customer_support_greeting" })
  .where(status: "active")
  .first!

support_dataset = PromptTracker::Dataset.create!(
  testable: support_greeting_v3,
  name: "Customer Scenarios",
  description: "Common customer support scenarios for testing greetings"
)

support_dataset.dataset_rows.create!([
  {
    row_data: {
      "customer_name" => "John Smith",
      "issue_category" => "billing"
    },
    source: "manual"
  },
  {
    row_data: {
      "customer_name" => "Sarah Johnson",
      "issue_category" => "technical"
    },
    source: "manual"
  },
  {
    row_data: {
      "customer_name" => "Mike Davis",
      "issue_category" => "account"
    },
    source: "manual"
  },
  {
    row_data: {
      "customer_name" => "Emily Chen",
      "issue_category" => "general"
    },
    source: "manual"
  },
  {
    row_data: {
      "customer_name" => "Alex Martinez",
      "issue_category" => "refund"
    },
    source: "manual"
  }
])

puts "  ✓ Created customer support greeting dataset (5 rows)"

# ============================================================================
# 2. Email Summary Generator Dataset
# ============================================================================

email_summary_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "email_summary_generator" })
  .where(status: "active")
  .first!

email_dataset = PromptTracker::Dataset.create!(
  testable: email_summary_v1,
  name: "Email Threads",
  description: "Sample email threads for testing summarization"
)

email_dataset.dataset_rows.create!([
  {
    row_data: {
      "email_thread" => <<~EMAIL.strip
        From: alice@example.com
        To: team@example.com
        Subject: Q4 Planning Meeting

        Hi team,

        I'd like to schedule our Q4 planning meeting for next week.
        We need to discuss budget allocation and project priorities.

        Best,
        Alice

        ---

        From: bob@example.com
        To: alice@example.com, team@example.com
        Subject: Re: Q4 Planning Meeting

        Tuesday or Wednesday works for me. I'll prepare the budget report.

        Bob

        ---

        From: carol@example.com
        To: alice@example.com, team@example.com
        Subject: Re: Q4 Planning Meeting

        Wednesday is better for me. I'll have the project status updates ready.

        Carol
      EMAIL
    },
    source: "manual"
  },
  {
    row_data: {
      "email_thread" => <<~EMAIL.strip
        From: support@vendor.com
        To: procurement@company.com
        Subject: Contract Renewal

        Dear Customer,

        Your annual contract expires on December 31st.
        We're offering a 15% discount for early renewal.

        Best regards,
        Vendor Support

        ---

        From: procurement@company.com
        To: support@vendor.com
        Subject: Re: Contract Renewal

        Thank you. We'd like to discuss the renewal terms.
        Can we schedule a call for next week?

        Regards,
        Procurement Team
      EMAIL
    },
    source: "manual"
  },
  {
    row_data: {
      "email_thread" => <<~EMAIL.strip
        From: hr@company.com
        To: all@company.com
        Subject: Holiday Schedule Reminder

        Please remember to submit your holiday requests by Friday.
        The office will be closed from Dec 24-26.

        HR Team
      EMAIL
    },
    source: "manual"
  }
])

puts "  ✓ Created email summary dataset (3 rows)"

# ============================================================================
# 3. Code Review Assistant Dataset
# ============================================================================

code_review_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "code_review_assistant" })
  .where(status: "active")
  .first!

code_review_dataset = PromptTracker::Dataset.create!(
  testable: code_review_v1,
  name: "Code Samples",
  description: "Code samples for testing code review functionality"
)

code_review_dataset.dataset_rows.create!([
  {
    row_data: {
      "language" => "ruby",
      "code" => <<~CODE.strip
        def calculate_discount(price, discount)
          price - (price * discount / 100)
        end
      CODE
    },
    source: "manual"
  },
  {
    row_data: {
      "language" => "python",
      "code" => <<~CODE.strip
        def fetch_user_data(user_id):
            try:
                response = requests.get(f"/api/users/{user_id}")
                return response.json()
            except:
                return None
      CODE
    },
    source: "manual"
  },
  {
    row_data: {
      "language" => "javascript",
      "code" => <<~CODE.strip
        async function processItems(items) {
          for (let i = 0; i < items.length; i++) {
            await saveItem(items[i]);
          }
          return items.length;
        }
      CODE
    },
    source: "manual"
  },
  {
    row_data: {
      "language" => "ruby",
      "code" => <<~CODE.strip
        class User < ApplicationRecord
          def full_name
            first_name + ' ' + last_name
          end

          def send_welcome_email
            UserMailer.welcome(self).deliver_now
          end
        end
      CODE
    },
    source: "manual"
  }
])

puts "  ✓ Created code review dataset (4 rows)"

puts "\n  ✅ Created 3 datasets for prompt versions (12 total rows)"
