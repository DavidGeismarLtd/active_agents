# frozen_string_literal: true

# ============================================================================
# FUNCTION LIBRARY SEEDS
# ============================================================================
# This file creates example functions for the Function Registry.
# These demonstrate different use cases and serve as templates for users.

puts "\n🔧 Seeding Function Library..."

# Clean up existing data
PromptTracker::FunctionDefinition.destroy_all
PromptTracker::EnvironmentVariable.destroy_all

# ============================================================================
# Create Shared Environment Variables
# ============================================================================
puts "\n🔐 Creating shared environment variables..."

openweather_key = PromptTracker::EnvironmentVariable.create!(
  name: "OpenWeather API Key",
  key: "OPENWEATHER_API_KEY",
  value: "demo_openweather_key_12345",
  description: "API key for OpenWeatherMap service - used by weather-related functions"
)

bitly_key = PromptTracker::EnvironmentVariable.create!(
  name: "Bitly API Key",
  key: "BITLY_API_KEY",
  value: "demo_bitly_key_67890",
  description: "API key for Bitly URL shortening service"
)

sendgrid_key = PromptTracker::EnvironmentVariable.create!(
  name: "SendGrid API Key",
  key: "SENDGRID_API_KEY",
  value: "demo_sendgrid_key_abcdef",
  description: "API key for SendGrid email service"
)

puts "  ✓ Created 3 shared environment variables"

# ============================================================================
# 1. Weather API Function
# ============================================================================
weather_function = PromptTracker::FunctionDefinition.create!(
  name: "get_weather",
  description: "Get current weather for a city using OpenWeatherMap API",
  category: "api",
  tags: [ "weather", "api", "external" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(city:, units: "metric")
      require 'net/http'
      require 'json'

      api_key = env['OPENWEATHER_API_KEY']
      base_url = "https://api.openweathermap.org/data/2.5/weather"

      uri = URI(base_url)
      uri.query = URI.encode_www_form({
        q: city,
        units: units,
        appid: api_key
      })

      response = Net::HTTP.get_response(uri)
      data = JSON.parse(response.body)

      {
        city: data['name'],
        temperature: data['main']['temp'],
        feels_like: data['main']['feels_like'],
        humidity: data['main']['humidity'],
        description: data['weather'][0]['description'],
        units: units
      }
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "city" => {
        "type" => "string",
        "description" => "City name (e.g., 'London', 'New York')"
      },
      "units" => {
        "type" => "string",
        "enum" => [ "metric", "imperial", "standard" ],
        "description" => "Temperature units (metric=Celsius, imperial=Fahrenheit)",
        "default" => "metric"
      }
    },
    "required" => [ "city" ]
  },
  dependencies: [],
  example_input: {
    "city" => "Berlin",
    "units" => "metric"
  },
  example_output: {
    "city" => "Berlin",
    "temperature" => 15.2,
    "feels_like" => 14.1,
    "humidity" => 72,
    "description" => "partly cloudy",
    "units" => "metric"
  },
  created_by: "system"
)
weather_function.shared_environment_variables << openweather_key

puts "  ✓ Created weather API function (using shared OPENWEATHER_API_KEY)"

# ============================================================================
# 2. Simple Calculator Function
# ============================================================================
calculator_function = PromptTracker::FunctionDefinition.create!(
  name: "calculate",
  description: "Perform basic arithmetic operations (add, subtract, multiply, divide)",
  category: "utility",
  tags: [ "math", "calculator", "utility" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(operation:, a:, b:)
      case operation
      when "add"
        a + b
      when "subtract"
        a - b
      when "multiply"
        a * b
      when "divide"
        raise ArgumentError, "Cannot divide by zero" if b.zero?
        a.to_f / b
      else
        raise ArgumentError, "Unknown operation: #{operation}"
      end
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "operation" => {
        "type" => "string",
        "enum" => [ "add", "subtract", "multiply", "divide" ],
        "description" => "The arithmetic operation to perform"
      },
      "a" => {
        "type" => "number",
        "description" => "First operand"
      },
      "b" => {
        "type" => "number",
        "description" => "Second operand"
      }
    },
    "required" => [ "operation", "a", "b" ]
  },
  dependencies: [],
  example_input: {
    "operation" => "multiply",
    "a" => 6,
    "b" => 7
  },
  example_output: 42,
  created_by: "system"
)

puts "  ✓ Created calculator function"

# ============================================================================
# 3. Text Processing Function
# ============================================================================
text_processor = PromptTracker::FunctionDefinition.create!(
  name: "process_text",
  description: "Process text with various transformations (uppercase, lowercase, reverse, word count)",
  category: "utility",
  tags: [ "text", "string", "processing" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(text:, operation:)
      case operation
      when "uppercase"
        text.upcase
      when "lowercase"
        text.downcase
      when "reverse"
        text.reverse
      when "word_count"
        text.split.length
      when "char_count"
        text.length
      when "titlecase"
        text.split.map(&:capitalize).join(' ')
      else
        raise ArgumentError, "Unknown operation: #{operation}"
      end
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "text" => {
        "type" => "string",
        "description" => "The text to process"
      },
      "operation" => {
        "type" => "string",
        "enum" => [ "uppercase", "lowercase", "reverse", "word_count", "char_count", "titlecase" ],
        "description" => "The transformation to apply"
      }
    },
    "required" => [ "text", "operation" ]
  },
  dependencies: [],
  example_input: {
    "text" => "hello world",
    "operation" => "titlecase"
  },
  example_output: "Hello World",
  created_by: "system"
)

puts "  ✓ Created text processing function"

# ============================================================================
# 4. JSON Validator Function
# ============================================================================
json_validator = PromptTracker::FunctionDefinition.create!(
  name: "validate_json",
  description: "Validate JSON string and return parsed object or error details",
  category: "validation",
  tags: [ "json", "validation", "parsing" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(json_string:)
      require 'json'

      begin
        parsed = JSON.parse(json_string)
        {
          valid: true,
          data: parsed,
          error: nil
        }
      rescue JSON::ParserError => e
        {
          valid: false,
          data: nil,
          error: e.message
        }
      end
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "json_string" => {
        "type" => "string",
        "description" => "JSON string to validate"
      }
    },
    "required" => [ "json_string" ]
  },
  dependencies: [],
  example_input: {
    "json_string" => '{"name": "John", "age": 30}'
  },
  example_output: {
    "valid" => true,
    "data" => { "name" => "John", "age" => 30 },
    "error" => nil
  },
  created_by: "system"
)

puts "  ✓ Created JSON validator function"

# ============================================================================
# 5. URL Shortener Function (Mock)
# ============================================================================
url_shortener = PromptTracker::FunctionDefinition.create!(
  name: "shorten_url",
  description: "Shorten a URL using a URL shortening service API",
  category: "api",
  tags: [ "url", "api", "utility" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(url:)
      require 'net/http'
      require 'json'

      api_key = env['BITLY_API_KEY']

      uri = URI('https://api-ssl.bitly.com/v4/shorten')
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{api_key}"
      request['Content-Type'] = 'application/json'
      request.body = { long_url: url }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      data = JSON.parse(response.body)

      {
        original_url: url,
        short_url: data['link'],
        created_at: data['created_at']
      }
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "url" => {
        "type" => "string",
        "format" => "uri",
        "description" => "The URL to shorten"
      }
    },
    "required" => [ "url" ]
  },
  dependencies: [],
  example_input: {
    "url" => "https://www.example.com/very/long/url/path"
  },
  example_output: {
    "original_url" => "https://www.example.com/very/long/url/path",
    "short_url" => "https://bit.ly/abc123",
    "created_at" => "2024-03-12T10:30:00Z"
  },
  created_by: "system"
)
url_shortener.shared_environment_variables << bitly_key

puts "  ✓ Created URL shortener function (using shared BITLY_API_KEY)"

# ============================================================================
# 6. Email Validator Function
# ============================================================================
email_validator = PromptTracker::FunctionDefinition.create!(
  name: "validate_email",
  description: "Validate email address format and check domain MX records",
  category: "validation",
  tags: [ "email", "validation", "regex" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(email:)
      # Basic email regex pattern
      email_regex = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i

      format_valid = email.match?(email_regex)

      {
        email: email,
        format_valid: format_valid,
        has_at_symbol: email.include?('@'),
        has_domain: email.split('@').length == 2 && email.split('@')[1].include?('.'),
        local_part: email.split('@')[0],
        domain: email.split('@')[1]
      }
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "email" => {
        "type" => "string",
        "description" => "Email address to validate"
      }
    },
    "required" => [ "email" ]
  },
  dependencies: [],
  example_input: {
    "email" => "user@example.com"
  },
  example_output: {
    "email" => "user@example.com",
    "format_valid" => true,
    "has_at_symbol" => true,
    "has_domain" => true,
    "local_part" => "user",
    "domain" => "example.com"
  },
  created_by: "system"
)

puts "  ✓ Created email validator function"

# ============================================================================
# 7. Random Generator Function
# ============================================================================
random_generator = PromptTracker::FunctionDefinition.create!(
  name: "generate_random",
  description: "Generate random data (numbers, strings, UUIDs, passwords)",
  category: "utility",
  tags: [ "random", "generator", "uuid" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(type:, length: 10)
      require 'securerandom'

      case type
      when "number"
        rand(1..length)
      when "string"
        SecureRandom.alphanumeric(length)
      when "uuid"
        SecureRandom.uuid
      when "hex"
        SecureRandom.hex(length / 2)
      when "password"
        # Generate password with letters, numbers, and symbols
        chars = [('a'..'z'), ('A'..'Z'), ('0'..'9'), ['!', '@', '#', '$', '%']].map(&:to_a).flatten
        Array.new(length) { chars.sample }.join
      else
        raise ArgumentError, "Unknown type: #{type}"
      end
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "type" => {
        "type" => "string",
        "enum" => [ "number", "string", "uuid", "hex", "password" ],
        "description" => "Type of random data to generate"
      },
      "length" => {
        "type" => "integer",
        "description" => "Length of generated data (not applicable for UUID)",
        "default" => 10
      }
    },
    "required" => [ "type" ]
  },
  dependencies: [],
  example_input: {
    "type" => "password",
    "length" => 16
  },
  example_output: "aB3$xY9@mK2#pQ5!",
  created_by: "system"
)

puts "  ✓ Created random generator function"

# ============================================================================
# 8. Date/Time Formatter Function
# ============================================================================
datetime_formatter = PromptTracker::FunctionDefinition.create!(
  name: "format_datetime",
  description: "Format and manipulate dates and times",
  category: "utility",
  tags: [ "date", "time", "formatting" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(datetime_string:, format:, timezone: "UTC")
      require 'time'

      dt = Time.parse(datetime_string)

      case format
      when "iso8601"
        dt.iso8601
      when "rfc2822"
        dt.rfc2822
      when "unix"
        dt.to_i
      when "human"
        dt.strftime("%B %d, %Y at %I:%M %p")
      when "date_only"
        dt.strftime("%Y-%m-%d")
      when "time_only"
        dt.strftime("%H:%M:%S")
      when "custom"
        dt.strftime(timezone)
      else
        dt.to_s
      end
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "datetime_string" => {
        "type" => "string",
        "description" => "Date/time string to parse"
      },
      "format" => {
        "type" => "string",
        "enum" => [ "iso8601", "rfc2822", "unix", "human", "date_only", "time_only", "custom" ],
        "description" => "Output format"
      },
      "timezone" => {
        "type" => "string",
        "description" => "Timezone (or custom strftime format if format=custom)",
        "default" => "UTC"
      }
    },
    "required" => [ "datetime_string", "format" ]
  },
  dependencies: [],
  example_input: {
    "datetime_string" => "2024-03-12 14:30:00",
    "format" => "human"
  },
  example_output: "March 12, 2024 at 02:30 PM",
  created_by: "system"
)

puts "  ✓ Created date/time formatter function"

# ============================================================================
# 9. News API Function (for News Analyst)
# ============================================================================
news_api_function = PromptTracker::FunctionDefinition.create!(
  name: "fetch_news_articles",
  description: "Fetch latest news articles from GNews API for a given topic. IMPORTANT: The 'topic' parameter must be a simple search phrase without commas or special characters. Use spaces to separate keywords (e.g., 'artificial intelligence' or 'cybersecurity news'). Do NOT use commas like 'AI, machine learning' - this will cause a syntax error.",
  category: "api",
  tags: [ "news", "api", "media" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(topic:, language: "en", page_size: 10)
      require 'net/http'
      require 'json'
      require 'uri'

      api_key = env['GNEWS_API_KEY']
      base_url = "https://gnews.io/api/v4/search"

      # GNews API parameters
      params = {
        q: topic,
        lang: language,
        max: [page_size, 10].min, # GNews free tier max is 10
        apikey: api_key
      }

      uri = URI(base_url)
      uri.query = URI.encode_www_form(params)

      response = Net::HTTP.get_response(uri)
      data = JSON.parse(response.body)

      if response.code == '200' && data['articles']
        {
          total_results: data['totalArticles'],
          articles: data['articles'].map do |article|
            {
              title: article['title'],
              description: article['description'],
              content: article['content'],
              url: article['url'],
              image: article['image'],
              source: article['source']['name'],
              published_at: article['publishedAt']
            }
          end
        }
      else
        { error: data['errors']&.first || data['message'] || 'Failed to fetch news' }
      end
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "topic" => {
        "type" => "string",
        "description" => "News topic or search query. Use simple phrases with spaces only (e.g., 'artificial intelligence', 'climate change policy'). Do NOT use commas, quotes, or special operators."
      },
      "language" => {
        "type" => "string",
        "description" => "Language code (e.g., 'en', 'fr', 'es', 'de')",
        "default" => "en"
      },
      "page_size" => {
        "type" => "integer",
        "description" => "Number of articles to return (max 10 for free tier)",
        "default" => 10
      }
    },
    "required" => [ "topic" ]
  },
  dependencies: [],
  example_input: {
    "topic" => "artificial intelligence",
    "language" => "en",
    "page_size" => 5
  },
  example_output: {
    "total_results" => 1247,
    "articles" => [
      {
        "title" => "AI Breakthrough in Medical Diagnosis",
        "description" => "New AI system achieves 95% accuracy...",
        "url" => "https://example.com/article",
        "source" => "TechNews",
        "published_at" => "2024-03-12T10:30:00Z",
        "author" => "Jane Smith"
      }
    ]
  },
  created_by: "system"
)

gnews_api_key = PromptTracker::EnvironmentVariable.create!(
  name: "GNews API Key",
  key: "GNEWS_API_KEY",
  value: "8a938f749f805f47ccd94712b7d32828",
  description: "API key for GNews.io - used for fetching news articles"
)
news_api_function.shared_environment_variables << gnews_api_key

puts "  ✓ Created news API function (using shared GNEWS_API_KEY)"

# ============================================================================
# 10. Flight Search Function (for Travel Booking Assistant)
# ============================================================================
flight_search_function = PromptTracker::FunctionDefinition.create!(
  name: "search_flights",
  description: "Search for available flights between two airports",
  category: "travel",
  tags: [ "travel", "flights", "booking" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(origin:, destination:, date:, passengers: 1)
      require 'date'

      # Mock flight search - in production, this would call a real flight API
      departure_date = Date.parse(date)

      # Generate mock flight results
      flights = [
        {
          flight_id: "FL#{rand(1000..9999)}",
          airline: ["United", "Delta", "American", "Southwest"].sample,
          departure_time: "#{date}T08:00:00Z",
          arrival_time: "#{date}T12:30:00Z",
          price: rand(200..800),
          currency: "USD",
          available_seats: rand(10..50),
          duration_minutes: 270
        },
        {
          flight_id: "FL#{rand(1000..9999)}",
          airline: ["United", "Delta", "American", "Southwest"].sample,
          departure_time: "#{date}T14:00:00Z",
          arrival_time: "#{date}T18:30:00Z",
          price: rand(200..800),
          currency: "USD",
          available_seats: rand(10..50),
          duration_minutes: 270
        }
      ]

      {
        origin: origin,
        destination: destination,
        date: date,
        passengers: passengers,
        flights: flights
      }
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "origin" => {
        "type" => "string",
        "description" => "Origin airport code (e.g., JFK, LAX)"
      },
      "destination" => {
        "type" => "string",
        "description" => "Destination airport code"
      },
      "date" => {
        "type" => "string",
        "description" => "Departure date in YYYY-MM-DD format"
      },
      "passengers" => {
        "type" => "integer",
        "description" => "Number of passengers",
        "default" => 1
      }
    },
    "required" => [ "origin", "destination", "date" ]
  },
  dependencies: [],
  example_input: {
    "origin" => "JFK",
    "destination" => "LAX",
    "date" => "2024-04-15",
    "passengers" => 2
  },
  example_output: {
    "origin" => "JFK",
    "destination" => "LAX",
    "date" => "2024-04-15",
    "passengers" => 2,
    "flights" => [
      {
        "flight_id" => "FL1234",
        "airline" => "Delta",
        "departure_time" => "2024-04-15T08:00:00Z",
        "arrival_time" => "2024-04-15T12:30:00Z",
        "price" => 450,
        "currency" => "USD",
        "available_seats" => 25,
        "duration_minutes" => 270
      }
    ]
  },
  created_by: "system"
)

puts "  ✓ Created flight search function"

# ============================================================================
# 11. Hotel Search Function (for Travel Booking Assistant)
# ============================================================================
hotel_search_function = PromptTracker::FunctionDefinition.create!(
  name: "search_hotels",
  description: "Search for available hotels in a city",
  category: "travel",
  tags: [ "travel", "hotels", "booking" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(city:, check_in:, check_out:, guests: 2)
      require 'date'

      # Mock hotel search - in production, this would call a real hotel API
      hotels = [
        {
          hotel_id: "HTL#{rand(1000..9999)}",
          name: "Grand Plaza Hotel",
          address: "123 Main St, #{city}",
          star_rating: 4,
          price_per_night: rand(150..300),
          currency: "USD",
          available_rooms: rand(5..20),
          amenities: ["WiFi", "Pool", "Gym", "Restaurant"],
          distance_from_center_km: rand(1.0..5.0).round(1)
        },
        {
          hotel_id: "HTL#{rand(1000..9999)}",
          name: "Budget Inn",
          address: "456 Oak Ave, #{city}",
          star_rating: 3,
          price_per_night: rand(80..150),
          currency: "USD",
          available_rooms: rand(5..20),
          amenities: ["WiFi", "Parking"],
          distance_from_center_km: rand(2.0..8.0).round(1)
        }
      ]

      {
        city: city,
        check_in: check_in,
        check_out: check_out,
        guests: guests,
        hotels: hotels
      }
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "city" => {
        "type" => "string",
        "description" => "City name to search for hotels"
      },
      "check_in" => {
        "type" => "string",
        "description" => "Check-in date in YYYY-MM-DD format"
      },
      "check_out" => {
        "type" => "string",
        "description" => "Check-out date in YYYY-MM-DD format"
      },
      "guests" => {
        "type" => "integer",
        "description" => "Number of guests",
        "default" => 2
      }
    },
    "required" => [ "city", "check_in", "check_out" ]
  },
  dependencies: [],
  example_input: {
    "city" => "Paris",
    "check_in" => "2024-05-01",
    "check_out" => "2024-05-05",
    "guests" => 2
  },
  example_output: {
    "city" => "Paris",
    "check_in" => "2024-05-01",
    "check_out" => "2024-05-05",
    "guests" => 2,
    "hotels" => [
      {
        "hotel_id" => "HTL5678",
        "name" => "Grand Plaza Hotel",
        "address" => "123 Main St, Paris",
        "star_rating" => 4,
        "price_per_night" => 220,
        "currency" => "USD",
        "available_rooms" => 12,
        "amenities" => [ "WiFi", "Pool", "Gym", "Restaurant" ],
        "distance_from_center_km" => 2.3
      }
    ]
  },
  created_by: "system"
)

puts "  ✓ Created hotel search function"

# ============================================================================
# 12. Product Search Function (for E-commerce Assistant)
# ============================================================================
product_search_function = PromptTracker::FunctionDefinition.create!(
  name: "search_products",
  description: "Search for products in the e-commerce catalog",
  category: "ecommerce",
  tags: [ "ecommerce", "products", "search" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(query:, category: nil, max_price: nil, in_stock: true)
      # Mock product search - in production, this would query a real database
      products = [
        {
          product_id: "PROD#{rand(10000..99999)}",
          name: "#{query.capitalize} Pro",
          description: "High-quality #{query} with advanced features",
          price: rand(50..500),
          currency: "USD",
          category: category || "Electronics",
          in_stock: true,
          stock_quantity: rand(10..100),
          rating: rand(3.5..5.0).round(1),
          image_url: "https://example.com/images/product1.jpg"
        },
        {
          product_id: "PROD#{rand(10000..99999)}",
          name: "#{query.capitalize} Basic",
          description: "Affordable #{query} for everyday use",
          price: rand(20..200),
          currency: "USD",
          category: category || "Electronics",
          in_stock: true,
          stock_quantity: rand(10..100),
          rating: rand(3.0..4.5).round(1),
          image_url: "https://example.com/images/product2.jpg"
        }
      ]

      # Filter by max_price if provided
      products = products.select { |p| p[:price] <= max_price } if max_price

      # Filter by in_stock if requested
      products = products.select { |p| p[:in_stock] } if in_stock

      {
        query: query,
        category: category,
        max_price: max_price,
        in_stock_only: in_stock,
        results_count: products.length,
        products: products
      }
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "query" => {
        "type" => "string",
        "description" => "Search query for products"
      },
      "category" => {
        "type" => "string",
        "description" => "Product category filter (optional)"
      },
      "max_price" => {
        "type" => "number",
        "description" => "Maximum price filter (optional)"
      },
      "in_stock" => {
        "type" => "boolean",
        "description" => "Only show in-stock items",
        "default" => true
      }
    },
    "required" => [ "query" ]
  },
  dependencies: [],
  example_input: {
    "query" => "laptop",
    "category" => "Electronics",
    "max_price" => 1000,
    "in_stock" => true
  },
  example_output: {
    "query" => "laptop",
    "category" => "Electronics",
    "max_price" => 1000,
    "in_stock_only" => true,
    "results_count" => 2,
    "products" => [
      {
        "product_id" => "PROD12345",
        "name" => "Laptop Pro",
        "description" => "High-quality laptop with advanced features",
        "price" => 899,
        "currency" => "USD",
        "category" => "Electronics",
        "in_stock" => true,
        "stock_quantity" => 45,
        "rating" => 4.7,
        "image_url" => "https://example.com/images/product1.jpg"
      }
    ]
  },
  created_by: "system"
)

puts "  ✓ Created product search function"

# ============================================================================
# 13. Order Status Function (for E-commerce Assistant)
# ============================================================================
order_status_function = PromptTracker::FunctionDefinition.create!(
  name: "get_order_status",
  description: "Get the status and details of a customer order",
  category: "ecommerce",
  tags: [ "ecommerce", "orders", "tracking" ],
  language: "ruby",
  code: <<~'RUBY',
    def execute(order_id:)
      require 'date'

      # Mock order lookup - in production, this would query a real database
      statuses = ["processing", "shipped", "delivered", "cancelled"]
      carriers = ["UPS", "FedEx", "USPS", "DHL"]

      status = statuses.sample
      order_date = (Date.today - rand(1..30)).to_s

      result = {
        order_id: order_id,
        status: status,
        order_date: "#{order_date}T10:30:00Z",
        items: [
          {
            product_id: "PROD#{rand(10000..99999)}",
            name: "Sample Product",
            quantity: rand(1..3),
            price: rand(20..200)
          }
        ]
      }

      if status == "shipped" || status == "delivered"
        result[:tracking_number] = "1Z#{rand(100000000..999999999)}"
        result[:carrier] = carriers.sample
        result[:estimated_delivery] = (Date.today + rand(1..5)).to_s + "T00:00:00Z"
      end

      result
    end
  RUBY
  parameters: {
    "type" => "object",
    "properties" => {
      "order_id" => {
        "type" => "string",
        "description" => "The order ID to look up"
      }
    },
    "required" => [ "order_id" ]
  },
  dependencies: [],
  example_input: {
    "order_id" => "ORD-2024-12345"
  },
  example_output: {
    "order_id" => "ORD-2024-12345",
    "status" => "shipped",
    "order_date" => "2024-03-01T10:30:00Z",
    "estimated_delivery" => "2024-03-15T00:00:00Z",
    "tracking_number" => "1Z123456789",
    "carrier" => "UPS",
    "items" => [
      {
        "product_id" => "PROD12345",
        "name" => "Sample Product",
        "quantity" => 2,
        "price" => 99
      }
    ]
  },
  created_by: "system"
)

puts "  ✓ Created order status function"

puts "\n✅ Function Library seeded:"
puts "   - 4 shared environment variables"
puts "   - 13 example functions (3 using shared variables)"
puts "\n📦 Functions by category:"
puts "   - News: fetch_news_articles"
puts "   - Travel: search_flights, search_hotels"
puts "   - E-commerce: search_products, get_order_status"
