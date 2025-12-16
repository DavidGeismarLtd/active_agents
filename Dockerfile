# Use official Ruby image
FROM ruby:3.3.0

# Install dependencies
RUN apt-get update -qq && \
    apt-get install -y \
    build-essential \
    libpq-dev \
    nodejs \
    npm \
    postgresql-client \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy dependency files and directories needed by gemspec
COPY Gemfile Gemfile.lock ./
COPY prompt_tracker.gemspec ./
COPY lib ./lib
COPY app ./app
COPY config ./config
COPY db ./db
COPY MIT-LICENSE Rakefile README.md ./

RUN bundle install

# Copy the rest of the application
COPY . .

# Copy and set permissions for entrypoint script
COPY docker-entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/docker-entrypoint.sh

# Precompile assets (if needed)
# RUN bundle exec rails assets:precompile

# Expose port 3000
EXPOSE 3000

# Set entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]

# Default command
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
