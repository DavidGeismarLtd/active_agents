# frozen_string_literal: true

# ============================================================================
# Prompts with Response API Tools (Web Search, Code Interpreter, Functions)
# ============================================================================

puts "  Creating prompts with Response API tools..."

# ============================================================================
# 1. Research Assistant Prompt (Web Search)
# ============================================================================

research_prompt = PromptTracker::Prompt.create!(
  name: "research_assistant",
  description: "Researches topics using web search and provides sourced answers",
  category: "research",
  tags: [ "web-search", "research", "citations" ],
  created_by: "research-team@example.com"
)

research_prompt.prompt_versions.create!(
  system_prompt: <<~SYSTEM.strip,
    You are a research assistant. Your role is to:
    1. Use web search to find accurate, up-to-date information
    2. Always cite your sources with URLs
    3. Synthesize information from multiple sources
    4. Present findings clearly and objectively
    5. Note when information may be outdated or uncertain

    Always use web search for factual queries. Never make up information.
  SYSTEM
  user_prompt: "Research the following topic and provide a well-sourced answer: {{query}}",
  status: "active",
  variables_schema: [
    { "name" => "query", "type" => "string", "required" => true }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "responses",
    "model" => "gpt-4o",
    "temperature" => 0.7,
    "max_tokens" => 2000,
    "tools" => [ "web_search" ]
  },
  notes: "Uses web search to research topics with source citations",
  created_by: "research-team@example.com"
)

puts "  ✓ Created research assistant prompt with web search"

# ============================================================================
# 2. Competitive Intelligence Prompt (Web Search with Domain Focus)
# ============================================================================

competitor_prompt = PromptTracker::Prompt.create!(
  name: "competitive_intelligence",
  description: "Researches competitors using web search from authoritative sources",
  category: "business",
  tags: [ "web-search", "competitive-analysis", "business" ],
  created_by: "strategy-team@example.com"
)

competitor_prompt.prompt_versions.create!(
  system_prompt: <<~SYSTEM.strip,
    You are a competitive intelligence assistant. Your role is to:
    1. Research competitors using authoritative business sources
    2. Prioritize sources like Bloomberg, Reuters, TechCrunch, company websites
    3. Provide market analysis and competitive positioning
    4. Cite sources for all claims
    5. Focus on factual, verifiable information

    Use web search to find the latest competitive intelligence.
  SYSTEM
  user_prompt: "Provide a competitive analysis of {{company}} in the {{industry}} industry. Focus on market position, recent developments, and competitive advantages.",
  status: "active",
  variables_schema: [
    { "name" => "company", "type" => "string", "required" => true },
    { "name" => "industry", "type" => "string", "required" => true }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "responses",
    "model" => "gpt-4o",
    "temperature" => 0.5,
    "max_tokens" => 3000,
    "tools" => [ "web_search" ]
  },
  notes: "Competitive intelligence with focus on authoritative business sources",
  created_by: "strategy-team@example.com"
)

puts "  ✓ Created competitive intelligence prompt with web search"

# ============================================================================
# 3. Data Analysis Prompt (Code Interpreter)
# ============================================================================

data_analysis_prompt = PromptTracker::Prompt.create!(
  name: "data_analyst",
  description: "Analyzes data using Python code execution",
  category: "analytics",
  tags: [ "code-interpreter", "data-analysis", "statistics" ],
  created_by: "data-team@example.com"
)

data_analysis_prompt.prompt_versions.create!(
  system_prompt: <<~SYSTEM.strip,
    You are a data analysis assistant. Your role is to:
    1. Use Python code to analyze data provided by users
    2. Create visualizations (charts, graphs) when helpful
    3. Calculate statistics and trends
    4. Explain your analysis clearly
    5. Export results as needed

    Always execute code to verify calculations. Show your work with clear explanations.
  SYSTEM
  user_prompt: "Analyze the following data and provide insights:\n\n{{data}}\n\nProvide: {{analysis_type}}",
  status: "active",
  variables_schema: [
    { "name" => "data", "type" => "string", "required" => true },
    { "name" => "analysis_type", "type" => "string", "required" => false, "default" => "statistical summary and trends" }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "responses",
    "model" => "gpt-4o",
    "temperature" => 0.3,
    "max_tokens" => 4000,
    "tools" => [ "code_interpreter" ]
  },
  notes: "Data analysis with Python code execution for accurate calculations",
  created_by: "data-team@example.com"
)

puts "  ✓ Created data analysis prompt with code interpreter"

# ============================================================================
# 4. Financial Modeling Prompt (Code Interpreter with Visualizations)
# ============================================================================

finance_prompt = PromptTracker::Prompt.create!(
  name: "financial_modeler",
  description: "Creates financial models and visualizations using Python",
  category: "finance",
  tags: [ "code-interpreter", "finance", "visualization" ],
  created_by: "finance-team@example.com"
)

finance_prompt.prompt_versions.create!(
  system_prompt: <<~SYSTEM.strip,
    You are a financial modeling assistant. Your role is to:
    1. Build financial models using Python (pandas, numpy)
    2. Create charts and visualizations (matplotlib, plotly)
    3. Calculate financial metrics (ROI, NPV, IRR)
    4. Generate reports and export to files
    5. Explain financial concepts clearly

    Always use code for calculations. Create visualizations for complex data.
  SYSTEM
  user_prompt: "Create a financial model for: {{scenario}}\n\nInclude calculations for: {{metrics}}",
  status: "active",
  variables_schema: [
    { "name" => "scenario", "type" => "string", "required" => true },
    { "name" => "metrics", "type" => "string", "required" => false, "default" => "ROI, growth rate, and projections" }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "responses",
    "model" => "gpt-4o",
    "temperature" => 0.3,
    "max_tokens" => 4000,
    "tools" => [ "code_interpreter" ]
  },
  notes: "Financial modeling with visualizations and file export",
  created_by: "finance-team@example.com"
)

puts "  ✓ Created financial modeling prompt with code interpreter"

# ============================================================================
# 5. Travel Booking Assistant (Function Calls)
# ============================================================================

travel_prompt = PromptTracker::Prompt.create!(
  name: "travel_booking_assistant",
  description: "Helps users plan and book travel using function calls",
  category: "travel",
  tags: [ "functions", "travel", "booking" ],
  created_by: "travel-team@example.com"
)

travel_prompt.prompt_versions.create!(
  system_prompt: <<~SYSTEM.strip,
    You are a travel booking assistant. Your role is to:
    1. Help users search for flights and hotels
    2. Check weather at destinations
    3. Book travel arrangements when requested
    4. Provide travel recommendations and tips

    Use the available functions to look up real-time information.
    Always confirm booking details with the user before finalizing.
  SYSTEM
  user_prompt: "Help me plan travel: {{request}}",
  status: "active",
  variables_schema: [
    { "name" => "request", "type" => "string", "required" => true }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "responses",
    "model" => "gpt-4o",
    "temperature" => 0.7,
    "max_tokens" => 2000,
    "tools" => [ "functions" ],
    "tool_config" => {
      "functions" => [
        {
          "name" => "search_flights",
          "description" => "Search for available flights between two airports",
          "output_description" => "Returns a JSON array of flight objects with fields: flight_id (string), airline (string), departure_time (ISO 8601 datetime), arrival_time (ISO 8601 datetime), price (number), currency (string), available_seats (number), duration_minutes (number)",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "origin" => { "type" => "string", "description" => "Origin airport code (e.g., JFK, LAX)" },
              "destination" => { "type" => "string", "description" => "Destination airport code" },
              "date" => { "type" => "string", "description" => "Departure date in YYYY-MM-DD format" },
              "passengers" => { "type" => "integer", "description" => "Number of passengers" }
            },
            "required" => [ "origin", "destination", "date" ]
          }
        },
        {
          "name" => "search_hotels",
          "description" => "Search for available hotels in a city",
          "output_description" => "Returns a JSON array of hotel objects with fields: hotel_id (string), name (string), address (string), star_rating (number 1-5), price_per_night (number), currency (string), available_rooms (number), amenities (array of strings), distance_from_center_km (number)",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "city" => { "type" => "string", "description" => "City name to search for hotels" },
              "check_in" => { "type" => "string", "description" => "Check-in date in YYYY-MM-DD" },
              "check_out" => { "type" => "string", "description" => "Check-out date in YYYY-MM-DD" },
              "guests" => { "type" => "integer", "description" => "Number of guests" }
            },
            "required" => [ "city", "check_in", "check_out" ]
          }
        },
        {
          "name" => "get_weather",
          "description" => "Get weather forecast for a location",
          "output_description" => "Returns a JSON object with fields: temperature_celsius (number), temperature_fahrenheit (number), condition (string like 'sunny', 'cloudy', 'rainy'), humidity_percent (number), wind_speed_kmh (number), forecast (string description), precipitation_chance_percent (number)",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "location" => { "type" => "string", "description" => "City or location name" },
              "date" => { "type" => "string", "description" => "Date for weather forecast" }
            },
            "required" => [ "location" ]
          }
        },
        {
          "name" => "book_flight",
          "description" => "Book a specific flight",
          "output_description" => "Returns a JSON object with fields: booking_id (string), confirmation_code (string), status (string like 'confirmed', 'pending'), total_price (number), currency (string), booking_date (ISO 8601 datetime), passenger_details (object with name and seat assignment)",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "flight_id" => { "type" => "string", "description" => "The flight ID to book" },
              "passenger_name" => { "type" => "string", "description" => "Full name of the passenger" },
              "seat_preference" => { "type" => "string", "enum" => [ "window", "aisle", "middle" ] }
            },
            "required" => [ "flight_id", "passenger_name" ]
          }
        }
      ]
    }
  },
  notes: "Travel assistant with function calls for search and booking",
  created_by: "travel-team@example.com"
)

puts "  ✓ Created travel booking prompt with function calls"

# ============================================================================
# 6. E-commerce Assistant (Function Calls)
# ============================================================================

ecommerce_prompt = PromptTracker::Prompt.create!(
  name: "ecommerce_assistant",
  description: "Helps customers with product search, orders, and support",
  category: "ecommerce",
  tags: [ "functions", "ecommerce", "customer-support" ],
  created_by: "ecommerce-team@example.com"
)

ecommerce_prompt.prompt_versions.create!(
  system_prompt: <<~SYSTEM.strip,
    You are an e-commerce assistant. Your role is to:
    1. Help customers find products using search
    2. Check order status and shipping information
    3. Process returns and refunds
    4. Answer product questions
    5. Provide personalized recommendations

    Use the available functions to access the product catalog and order system.
    Be helpful, friendly, and efficient.
  SYSTEM
  user_prompt: "Customer inquiry: {{inquiry}}",
  status: "active",
  variables_schema: [
    { "name" => "inquiry", "type" => "string", "required" => true }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "responses",
    "model" => "gpt-4o",
    "temperature" => 0.7,
    "max_tokens" => 1500,
    "tools" => [ "functions" ],
    "tool_config" => {
      "functions" => [
        {
          "name" => "search_products",
          "description" => "Search for products in the catalog",
          "output_description" => "Returns a JSON array of product objects with fields: product_id (string), name (string), description (string), price (number), currency (string), category (string), in_stock (boolean), stock_quantity (number), rating (number 1-5), image_url (string)",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "query" => { "type" => "string", "description" => "Search query" },
              "category" => { "type" => "string", "description" => "Product category" },
              "max_price" => { "type" => "number", "description" => "Maximum price filter" },
              "in_stock" => { "type" => "boolean", "description" => "Only show in-stock items" }
            },
            "required" => [ "query" ]
          }
        },
        {
          "name" => "get_order_status",
          "description" => "Get the status of an order",
          "output_description" => "Returns a JSON object with fields: order_id (string), status (string like 'processing', 'shipped', 'delivered'), order_date (ISO 8601 datetime), estimated_delivery (ISO 8601 datetime), tracking_number (string), carrier (string), items (array of objects with product_id, name, quantity, price)",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "order_id" => { "type" => "string", "description" => "The order ID" }
            },
            "required" => [ "order_id" ]
          }
        },
        {
          "name" => "initiate_return",
          "description" => "Start a return process for an order",
          "output_description" => "Returns a JSON object with fields: return_id (string), status (string like 'initiated', 'approved'), return_label_url (string), refund_amount (number), currency (string), estimated_refund_date (ISO 8601 datetime), instructions (string)",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "order_id" => { "type" => "string", "description" => "The order ID" },
              "reason" => { "type" => "string", "description" => "Reason for return" },
              "items" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Item IDs to return" }
            },
            "required" => [ "order_id", "reason" ]
          }
        },
        {
          "name" => "get_product_details",
          "description" => "Get detailed information about a specific product",
          "output_description" => "Returns a JSON object with fields: product_id (string), name (string), full_description (string), price (number), currency (string), category (string), brand (string), specifications (object), in_stock (boolean), stock_quantity (number), rating (number), review_count (number), images (array of URLs), related_products (array of product_ids)",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "product_id" => { "type" => "string", "description" => "The product ID" }
            },
            "required" => [ "product_id" ]
          }
        }
      ]
    }
  },
  notes: "E-commerce assistant with product search, orders, and returns",
  created_by: "ecommerce-team@example.com"
)

puts "  ✓ Created e-commerce assistant prompt with function calls"

# ============================================================================
# 7. News Analyst Prompt (Web Search)
# ============================================================================

news_prompt = PromptTracker::Prompt.create!(
  name: "news_analyst",
  description: "Analyzes current events using web search",
  category: "media",
  tags: [ "web-search", "news", "analysis" ],
  created_by: "media-team@example.com"
)

news_prompt.prompt_versions.create!(
  system_prompt: <<~SYSTEM.strip,
    You are a news analyst assistant. Your role is to:
    1. Search for the latest news on requested topics
    2. Synthesize information from multiple news sources
    3. Provide balanced, objective analysis
    4. Cite all sources with publication dates
    5. Distinguish between facts and opinions

    Use web search to find current news. Always verify information across sources.
  SYSTEM
  user_prompt: "Provide a news analysis on: {{topic}}\n\nFocus on: {{focus_areas}}",
  status: "active",
  variables_schema: [
    { "name" => "topic", "type" => "string", "required" => true },
    { "name" => "focus_areas", "type" => "string", "required" => false, "default" => "recent developments and key stakeholders" }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "responses",
    "model" => "gpt-4o",
    "temperature" => 0.5,
    "max_tokens" => 3000,
    "tools" => [ "web_search" ]
  },
  notes: "News analysis with balanced multi-source reporting",
  created_by: "media-team@example.com"
)

puts "  ✓ Created news analyst prompt with web search"

# ============================================================================
# 8. Tech Support Assistant (Anthropic with Function Calls)
# ============================================================================

tech_support_prompt = PromptTracker::Prompt.create!(
  name: "tech_support_assistant_claude",
  description: "Provides technical support using Claude with function calls",
  category: "support",
  tags: [ "anthropic", "functions", "tech-support" ],
  created_by: "support-team@example.com"
)

tech_support_prompt.prompt_versions.create!(
  system_prompt: <<~SYSTEM.strip,
    You are a technical support assistant powered by Claude. Your role is to:
    1. Diagnose technical issues by gathering system information
    2. Look up error codes and known solutions
    3. Create support tickets when needed
    4. Provide step-by-step troubleshooting guidance
    5. Escalate complex issues to human agents

    Use the available functions to access the knowledge base and ticketing system.
    Be patient, thorough, and explain technical concepts clearly.
  SYSTEM
  user_prompt: "Technical issue: {{issue_description}}",
  status: "active",
  variables_schema: [
    { "name" => "issue_description", "type" => "string", "required" => true }
  ],
  model_config: {
    "provider" => "anthropic",
    "api" => "messages",
    "model" => "claude-sonnet-4-20250514",
    "temperature" => 0.5,
    "max_tokens" => 4096,
    "tools" => [ "functions" ],
    "tool_config" => {
      "functions" => [
        {
          "name" => "lookup_error_code",
          "description" => "Look up an error code in the knowledge base to find known solutions",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "error_code" => { "type" => "string", "description" => "The error code to look up (e.g., E1001, 0x80070005)" },
              "product" => { "type" => "string", "description" => "Product or system name" }
            },
            "required" => [ "error_code" ]
          }
        },
        {
          "name" => "get_system_status",
          "description" => "Check the status of a system or service",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "system_name" => { "type" => "string", "description" => "Name of the system to check" },
              "include_history" => { "type" => "boolean", "description" => "Include recent status history" }
            },
            "required" => [ "system_name" ]
          }
        },
        {
          "name" => "create_support_ticket",
          "description" => "Create a new support ticket for an issue",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "title" => { "type" => "string", "description" => "Brief title of the issue" },
              "description" => { "type" => "string", "description" => "Detailed description of the issue" },
              "priority" => { "type" => "string", "enum" => [ "low", "medium", "high", "critical" ], "description" => "Issue priority" },
              "category" => { "type" => "string", "description" => "Issue category (e.g., hardware, software, network)" }
            },
            "required" => [ "title", "description", "priority" ]
          }
        },
        {
          "name" => "search_knowledge_base",
          "description" => "Search the knowledge base for articles related to an issue",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "query" => { "type" => "string", "description" => "Search query" },
              "category" => { "type" => "string", "description" => "Article category filter" },
              "max_results" => { "type" => "integer", "description" => "Maximum number of results to return" }
            },
            "required" => [ "query" ]
          }
        }
      ]
    }
  },
  notes: "Anthropic Claude tech support with function calls for diagnostics and ticketing",
  created_by: "support-team@example.com"
)

puts "  ✓ Created tech support assistant prompt with Anthropic + function calls"

puts "\n  ✅ Created 8 prompts with API tools (web_search, code_interpreter, functions)"
