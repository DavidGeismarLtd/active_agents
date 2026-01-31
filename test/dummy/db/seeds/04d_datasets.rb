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

# ============================================================================
# CONVERSATIONAL DATASETS
# ============================================================================

puts "\n  Creating conversational datasets for multi-turn testing..."

# ============================================================================
# 11. Customer Support Greeting Conversational Dataset
# ============================================================================

support_conversational_dataset = PromptTracker::Dataset.create!(
  testable: support_greeting_v3,
  name: "Customer Support Conversations",
  description: "Multi-turn customer support conversation scenarios",
  dataset_type: :conversational
)

support_conversational_dataset.dataset_rows.create!([
  {
    row_data: {
      "customer_name" => "Jennifer Williams",
      "issue_category" => "billing",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are Jennifer Williams, a frustrated customer who was charged twice for the same subscription.
        You noticed the duplicate charge on your credit card statement this morning.
        Start by explaining the issue, then ask for a refund.
        If asked for details, provide: Order IDs #78901 and #78902, both charged on January 15th for $49.99 each.
        You want both charges refunded immediately and are considering canceling your subscription.
        Be firm but professional. Accept a solution if they offer immediate refund and a discount on next month.
      PROMPT
      "max_turns" => 8
    },
    source: "manual"
  },
  {
    row_data: {
      "customer_name" => "Robert Chen",
      "issue_category" => "technical",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are Robert Chen, a customer experiencing login issues with the mobile app.
        You've been trying to log in for the past hour but keep getting "Invalid credentials" error.
        You're certain your password is correct because it works on the website.
        Start by describing the problem. If asked, mention you're using an iPhone 15 with iOS 17.
        You've already tried restarting the app and your phone.
        Be patient and cooperative, willing to try troubleshooting steps.
        The issue should be resolved if they suggest clearing the app cache or reinstalling.
      PROMPT
      "max_turns" => 6
    },
    source: "manual"
  },
  {
    row_data: {
      "customer_name" => "Maria Garcia",
      "issue_category" => "account",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are Maria Garcia, trying to update your email address but the system won't let you.
        You recently got married and changed your email from maria.rodriguez@email.com to maria.garcia@email.com.
        When you try to update it in account settings, you get an error: "Email already in use."
        Start by explaining this issue. You're confused because the new email is YOUR email.
        If they ask, you created a second account by mistake with the new email last week but never used it.
        Be understanding and cooperative. Accept a solution to merge accounts or delete the unused one.
      PROMPT
      "max_turns" => 7
    },
    source: "manual"
  },
  {
    row_data: {
      "customer_name" => "David Thompson",
      "issue_category" => "refund",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are David Thompson, requesting a refund for a premium feature you purchased but never used.
        You bought the "Pro Analytics" add-on 3 months ago for $99/month but realized you don't need it.
        You haven't used any of the pro features and want a refund for all 3 months ($297 total).
        Start by politely requesting the refund. If they mention a refund policy, you didn't see it during purchase.
        Be reasonable - you'll accept a partial refund if full refund isn't possible.
        Also want to make sure the subscription is canceled so you're not charged again.
      PROMPT
      "max_turns" => 6
    },
    source: "manual"
  }
])

puts "  ✓ Created customer support conversational dataset (4 rows)"

# ============================================================================
# 12. Research Assistant Conversational Dataset
# ============================================================================

research_conversational_dataset = PromptTracker::Dataset.create!(
  testable: research_v1,
  name: "Research Conversations",
  description: "Multi-turn research conversations with follow-up questions",
  dataset_type: :conversational
)

research_conversational_dataset.dataset_rows.create!([
  {
    row_data: {
      "query" => "What are the health benefits of intermittent fasting?",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are a curious person researching intermittent fasting for personal health.
        Start with the initial query about health benefits.
        After receiving the answer, ask 2-3 follow-up questions based on the response, such as:
        - Which specific fasting schedule is most effective?
        - Are there any risks or side effects I should know about?
        - How long before I might see results?
        - Is it safe for someone with diabetes?
        Be genuinely curious and ask for clarification on scientific terms if they're used.
        Thank the assistant when you have enough information.
      PROMPT
      "max_turns" => 7
    },
    source: "manual"
  },
  {
    row_data: {
      "query" => "Explain the current state of fusion energy research",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are a science enthusiast researching fusion energy for a blog post.
        Start with the initial query about fusion energy.
        After the initial response, dig deeper with follow-up questions:
        - What was the recent breakthrough at the National Ignition Facility?
        - How does this compare to ITER's approach?
        - When might we realistically see commercial fusion power?
        - What are the main technical challenges still to overcome?
        Show knowledge of basic physics but ask for clarification on complex concepts.
        End by asking for the most reliable sources to cite.
      PROMPT
      "max_turns" => 8
    },
    source: "manual"
  },
  {
    row_data: {
      "query" => "What are the environmental impacts of cryptocurrency mining?",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are an environmental journalist researching cryptocurrency's carbon footprint.
        Start with the broad query about environmental impacts.
        Follow up with specific questions based on the response:
        - How does Bitcoin's energy consumption compare to Ethereum after the merge?
        - What percentage of mining uses renewable energy?
        - Are there any eco-friendly alternatives to proof-of-work?
        - What regulations are being proposed to address this?
        Be critical but fair, seeking balanced information.
        Ask for recent statistics and credible sources.
      PROMPT
      "max_turns" => 7
    },
    source: "manual"
  }
])

puts "  ✓ Created research assistant conversational dataset (3 rows)"

# ============================================================================
# 13. Travel Booking Assistant Conversational Dataset
# ============================================================================

travel_conversational_dataset = PromptTracker::Dataset.create!(
  testable: travel_v1,
  name: "Travel Booking Conversations",
  description: "Multi-turn travel booking scenarios with progressive detail gathering",
  dataset_type: :conversational
)

travel_conversational_dataset.dataset_rows.create!([
  {
    row_data: {
      "request" => "I need to plan a trip to Japan",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are planning a 2-week vacation to Japan in April for you and your spouse.
        Start with a vague request: "I need to plan a trip to Japan"
        Provide details progressively as the assistant asks:
        - Dates: April 10-24, 2026 (flexible by a few days)
        - Travelers: 2 adults
        - Departure city: Los Angeles (LAX)
        - Interests: Culture, food, temples, some nature
        - Budget: Moderate (not luxury, not budget)
        - Cities: Thinking Tokyo, Kyoto, maybe Osaka
        Ask questions about:
        - Best time to see cherry blossoms
        - Whether to get a JR Pass
        - Hotel recommendations in each city
        Be enthusiastic and open to suggestions.
      PROMPT
      "max_turns" => 10
    },
    source: "manual"
  },
  {
    row_data: {
      "request" => "I need a last-minute flight to Chicago",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are booking an urgent business trip to Chicago.
        Start with: "I need a last-minute flight to Chicago"
        Provide details when asked:
        - Need to fly out tomorrow morning (earliest possible)
        - Return in 3 days
        - Departing from: Boston (BOS)
        - Just yourself (1 passenger)
        - Prefer direct flights
        - Need to arrive before 2 PM for a meeting
        - Company is paying, so price is less important than timing
        Also ask about:
        - Airport hotel recommendations near O'Hare
        - Ground transportation options
        Be time-conscious and focused on logistics.
      PROMPT
      "max_turns" => 8
    },
    source: "manual"
  },
  {
    row_data: {
      "request" => "Family vacation to Orlando",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are planning a family vacation to Orlando with two kids (ages 7 and 10).
        Start with: "We want to take the kids to Orlando"
        Provide details progressively:
        - Dates: Summer break, late June or early July, 5-7 days
        - Travelers: 2 adults, 2 children
        - From: Denver
        - Main goal: Disney World, maybe Universal
        - Budget: Mid-range, want good value
        - Never been before, need advice
        Ask questions about:
        - Which parks to prioritize with kids these ages
        - Whether to stay on Disney property
        - How many days needed for parks
        - Weather concerns in summer
        Be excited but slightly overwhelmed by planning.
      PROMPT
      "max_turns" => 10
    },
    source: "manual"
  }
])

puts "  ✓ Created travel booking conversational dataset (3 rows)"

# ============================================================================
# 14. E-commerce Assistant Conversational Dataset
# ============================================================================

ecommerce_conversational_dataset = PromptTracker::Dataset.create!(
  testable: ecommerce_v1,
  name: "E-commerce Support Conversations",
  description: "Multi-turn customer service conversations for e-commerce",
  dataset_type: :conversational
)

ecommerce_conversational_dataset.dataset_rows.create!([
  {
    row_data: {
      "inquiry" => "I'm looking for a laptop for college",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are a college student shopping for a laptop for engineering classes.
        Start with: "I'm looking for a laptop for college"
        Provide details when asked:
        - Major: Mechanical Engineering (will need CAD software)
        - Budget: Around $1000-1500
        - Preferences: Good battery life, portable (will carry to classes)
        - Operating system: No strong preference, but familiar with Windows
        - Screen size: 14-15 inches preferred
        Ask questions about:
        - Which models can handle AutoCAD and SolidWorks
        - Student discounts available
        - Warranty options
        - Return policy if it doesn't work out
        Be price-conscious but willing to invest in quality.
      PROMPT
      "max_turns" => 9
    },
    source: "manual"
  },
  {
    row_data: {
      "inquiry" => "My order hasn't arrived and tracking shows it's lost",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are a customer whose package appears to be lost in transit.
        Start with: "My order hasn't arrived and tracking shows it's lost"
        Details to provide:
        - Order #: 45678
        - Ordered: 10 days ago
        - Expected delivery: 3 days ago
        - Tracking: Shows "Exception - Unable to locate package"
        - Item: Birthday gift for your daughter (her birthday is in 2 days)
        - Value: $150 wireless earbuds
        Be concerned and slightly frustrated, but polite.
        Want either:
        1. Immediate replacement with expedited shipping, OR
        2. Full refund so you can buy locally
        Ask about compensation for the inconvenience.
      PROMPT
      "max_turns" => 7
    },
    source: "manual"
  },
  {
    row_data: {
      "inquiry" => "I received the wrong item in my order",
      "interlocutor_simulation_prompt" => <<~PROMPT.strip,
        You are a customer who received the wrong product.
        Start with: "I received the wrong item in my order"
        Details when asked:
        - Order #: 89012
        - Ordered: Blue running shoes, size 10
        - Received: Red running shoes, size 8
        - Need the correct item for a marathon next month
        - Don't want to pay return shipping since it's their mistake
        - Package and shoes are in perfect condition
        Be reasonable but firm about not paying for their error.
        Ask about:
        - How quickly can they send the correct item
        - Do you need to return the wrong item first or can they cross-ship
        - Any compensation for the hassle
        Accept a solution that gets you the right shoes quickly.
      PROMPT
      "max_turns" => 8
    },
    source: "manual"
  }
])

puts "  ✓ Created e-commerce conversational dataset (3 rows)"

puts "\n  ✅ Created 10 single-turn datasets (39 rows) and 4 conversational datasets (13 rows)"
puts "  📊 Total: 14 datasets with 52 rows"
