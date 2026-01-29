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

# ============================================================================
# 4. Research Assistant Dataset (Web Search)
# ============================================================================

research_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "research_assistant" })
  .where(status: "active")
  .first!

research_dataset = PromptTracker::Dataset.create!(
  testable: research_v1,
  name: "Research Queries",
  description: "Sample research queries for testing web search functionality"
)

research_dataset.dataset_rows.create!([
  {
    row_data: {
      "query" => "What are the latest developments in quantum computing in 2026?"
    },
    source: "manual"
  },
  {
    row_data: {
      "query" => "Compare the environmental impact of electric vehicles vs hydrogen fuel cell vehicles"
    },
    source: "manual"
  },
  {
    row_data: {
      "query" => "What are the current FDA-approved treatments for Alzheimer's disease?"
    },
    source: "manual"
  }
])

puts "  ✓ Created research assistant dataset (3 rows)"

# ============================================================================
# 5. Competitive Intelligence Dataset (Web Search)
# ============================================================================

competitor_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "competitive_intelligence" })
  .where(status: "active")
  .first!

competitor_dataset = PromptTracker::Dataset.create!(
  testable: competitor_v1,
  name: "Competitive Analysis Scenarios",
  description: "Sample competitive analysis requests"
)

competitor_dataset.dataset_rows.create!([
  {
    row_data: {
      "company" => "Tesla",
      "industry" => "electric vehicles"
    },
    source: "manual"
  },
  {
    row_data: {
      "company" => "OpenAI",
      "industry" => "artificial intelligence"
    },
    source: "manual"
  },
  {
    row_data: {
      "company" => "Stripe",
      "industry" => "payment processing"
    },
    source: "manual"
  }
])

puts "  ✓ Created competitive intelligence dataset (3 rows)"

# ============================================================================
# 6. Data Analysis Dataset (Code Interpreter)
# ============================================================================

data_analysis_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "data_analyst" })
  .where(status: "active")
  .first!

data_analysis_dataset = PromptTracker::Dataset.create!(
  testable: data_analysis_v1,
  name: "Data Analysis Scenarios",
  description: "Sample datasets for testing data analysis with code interpreter"
)

data_analysis_dataset.dataset_rows.create!([
  {
    row_data: {
      "data" => "Sales data: Q1: $120k, Q2: $145k, Q3: $132k, Q4: $178k",
      "analysis_type" => "quarterly trends and year-over-year growth"
    },
    source: "manual"
  },
  {
    row_data: {
      "data" => "Customer ages: 25, 32, 28, 45, 38, 29, 52, 31, 27, 41, 36, 33",
      "analysis_type" => "statistical summary and age distribution"
    },
    source: "manual"
  },
  {
    row_data: {
      "data" => "Website traffic: Mon: 1200, Tue: 1450, Wed: 1380, Thu: 1520, Fri: 1890, Sat: 980, Sun: 850",
      "analysis_type" => "weekly patterns and peak traffic times"
    },
    source: "manual"
  }
])

puts "  ✓ Created data analysis dataset (3 rows)"

# ============================================================================
# 7. Financial Modeling Dataset (Code Interpreter)
# ============================================================================

finance_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "financial_modeler" })
  .where(status: "active")
  .first!

finance_dataset = PromptTracker::Dataset.create!(
  testable: finance_v1,
  name: "Financial Modeling Scenarios",
  description: "Sample financial scenarios for testing modeling capabilities"
)

finance_dataset.dataset_rows.create!([
  {
    row_data: {
      "scenario" => "5-year investment with $10,000 initial capital, 8% annual return",
      "metrics" => "ROI, compound growth, and final value"
    },
    source: "manual"
  },
  {
    row_data: {
      "scenario" => "SaaS business with $50k MRR, 10% monthly growth, $200k operating costs",
      "metrics" => "break-even point, runway, and 12-month projections"
    },
    source: "manual"
  },
  {
    row_data: {
      "scenario" => "Real estate investment: $500k property, 20% down payment, 4.5% interest rate, 30-year mortgage",
      "metrics" => "monthly payment, total interest, and equity buildup"
    },
    source: "manual"
  }
])

puts "  ✓ Created financial modeling dataset (3 rows)"

# ============================================================================
# 8. Travel Booking Assistant Dataset (Functions)
# ============================================================================

travel_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "travel_booking_assistant" })
  .where(status: "active")
  .first!

travel_dataset = PromptTracker::Dataset.create!(
  testable: travel_v1,
  name: "Travel Booking Scenarios",
  description: "Sample travel requests for testing booking functionality"
)

travel_dataset.dataset_rows.create!([
  {
    row_data: {
      "request" => "I need to fly from New York to San Francisco next Tuesday for a business meeting"
    },
    source: "manual"
  },
  {
    row_data: {
      "request" => "Find me a hotel in Paris for 3 nights starting March 15th, near the Eiffel Tower"
    },
    source: "manual"
  },
  {
    row_data: {
      "request" => "What's the weather like in Tokyo next week? I'm planning a trip"
    },
    source: "manual"
  }
])

puts "  ✓ Created travel booking dataset (3 rows)"

# ============================================================================
# 9. E-commerce Assistant Dataset (Functions)
# ============================================================================

ecommerce_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "ecommerce_assistant" })
  .where(status: "active")
  .first!

ecommerce_dataset = PromptTracker::Dataset.create!(
  testable: ecommerce_v1,
  name: "E-commerce Customer Inquiries",
  description: "Sample customer inquiries for testing e-commerce functionality"
)

ecommerce_dataset.dataset_rows.create!([
  {
    row_data: {
      "inquiry" => "I'm looking for wireless headphones under $100 with good battery life"
    },
    source: "manual"
  },
  {
    row_data: {
      "inquiry" => "What's the status of my order #12345? It was supposed to arrive yesterday"
    },
    source: "manual"
  },
  {
    row_data: {
      "inquiry" => "I need to return the blue sweater from order #67890, it doesn't fit"
    },
    source: "manual"
  }
])

puts "  ✓ Created e-commerce assistant dataset (3 rows)"

# ============================================================================
# 10. News Analyst Dataset (Web Search)
# ============================================================================

news_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "news_analyst" })
  .where(status: "active")
  .first!

news_dataset = PromptTracker::Dataset.create!(
  testable: news_v1,
  name: "News Analysis Topics",
  description: "Sample news topics for testing analysis functionality"
)

news_dataset.dataset_rows.create!([
  {
    row_data: {
      "topic" => "Artificial intelligence regulation in the European Union",
      "focus_areas" => "recent policy changes and industry reactions"
    },
    source: "manual"
  },
  {
    row_data: {
      "topic" => "Climate change initiatives at COP conferences",
      "focus_areas" => "commitments made and progress tracking"
    },
    source: "manual"
  },
  {
    row_data: {
      "topic" => "Cryptocurrency market trends",
      "focus_areas" => "major price movements and regulatory developments"
    },
    source: "manual"
  }
])

puts "  ✓ Created news analyst dataset (3 rows)"

puts "\n  ✅ Created 10 datasets for prompt versions (39 total rows)"
