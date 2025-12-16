#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails
rm -f /app/tmp/pids/server.pid

# Wait for database to be ready
echo "Waiting for database..."
until PGPASSWORD=$POSTGRES_PASSWORD psql -h "db" -U "$POSTGRES_USER" -c '\q' 2>/dev/null; do
  echo "Database is unavailable - sleeping"
  sleep 1
done
echo "Database is up!"

# Wait for Redis to be ready
echo "Waiting for Redis..."
until nc -z redis 6379 2>/dev/null; do
  echo "Redis is unavailable - sleeping"
  sleep 1
done
echo "Redis is up!"

# Prepare database (create, migrate, seed if needed)
# Since this is a Rails engine, we need to work in the dummy app directory
echo "Preparing database..."
cd test/dummy
# Drop and recreate database to ensure clean state
bundle exec rails db:drop db:create
# Install engine migrations first
bundle exec rails prompt_tracker:install:migrations
# Then run all migrations
bundle exec rails db:migrate
cd /app

# Execute the main command
exec "$@"
