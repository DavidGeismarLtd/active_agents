# Docker Setup for PromptTracker

This guide explains how to run PromptTracker using Docker and Docker Compose.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (version 20.10 or higher)
- [Docker Compose](https://docs.docker.com/compose/install/) (version 2.0 or higher)

## Quick Start

### 1. Build and Start All Services

```bash
docker-compose up --build
```

This will start:
- **PostgreSQL** database on port 5432
- **Redis** server on port 6379
- **Rails** web server on port 3000
- **Sidekiq** worker for background jobs

### 2. Access the Application

Open your browser and navigate to:
```
http://localhost:3000
```

### 3. Stop All Services

Press `Ctrl+C` in the terminal, or run:
```bash
docker-compose down
```

## Common Commands

### Using Make (Recommended)

A `Makefile` is provided for convenience:

```bash
# Show all available commands
make help

# Start services
make up              # Start in foreground
make up-d            # Start in background (detached)

# Stop services
make down            # Stop services
make down-v          # Stop and remove volumes

# View logs
make logs            # All services
make logs-web        # Web service only
make logs-sidekiq    # Sidekiq service only

# Development
make console         # Rails console
make shell           # Bash shell in web container
make test            # Run all tests
make rspec           # Run RSpec tests

# Database
make db-migrate      # Run migrations
make db-reset        # Reset database
make db-seed         # Seed database

# Maintenance
make rebuild         # Rebuild from scratch
make clean           # Clean up Docker resources
```

### Using Docker Compose Directly

#### Start Services in Background (Detached Mode)

```bash
docker-compose up -d
```

#### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f web
docker-compose logs -f sidekiq
```

#### Run Database Migrations

```bash
docker-compose exec web bundle exec rails db:migrate
```

#### Access Rails Console

```bash
docker-compose exec web bundle exec rails console
```

#### Run Tests

```bash
# RSpec tests
docker-compose exec web bundle exec rspec

# All tests
docker-compose exec web bin/test_all
```

#### Reset Database

```bash
docker-compose exec web bundle exec rails db:reset
```

#### Rebuild Containers

If you change the Gemfile or Dockerfile:
```bash
docker-compose down
docker-compose build --no-cache
docker-compose up
```

## Environment Variables

You can customize the setup by creating a `.env` file in the root directory:

```env
# Database
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=prompt_tracker_development

# Redis
REDIS_URL=redis://redis:6379/0

# Rails
RAILS_ENV=development
RAILS_MAX_THREADS=5

# LLM API Keys (optional)
OPENAI_API_KEY=your_openai_key
ANTHROPIC_API_KEY=your_anthropic_key
```

Then update `docker-compose.yml` to use the `.env` file:

```yaml
services:
  web:
    env_file:
      - .env
```

## Production Deployment

A separate `docker-compose.prod.yml` file is provided for production deployments.

### 1. Create Production Environment File

Create a `.env.production` file:

```env
# Required
POSTGRES_PASSWORD=your_secure_password_here
SECRET_KEY_BASE=your_secret_key_base_here

# Optional - customize as needed
POSTGRES_USER=postgres
POSTGRES_DB=prompt_tracker_production
PORT=3000
RAILS_MAX_THREADS=5

# LLM API Keys
OPENAI_API_KEY=your_openai_key
ANTHROPIC_API_KEY=your_anthropic_key
```

Generate a secure `SECRET_KEY_BASE`:
```bash
docker-compose run --rm web bundle exec rails secret
```

### 2. Deploy

```bash
# Load environment variables and start services
docker-compose -f docker-compose.prod.yml --env-file .env.production up -d
```

### 3. Setup Database

```bash
docker-compose -f docker-compose.prod.yml exec web bundle exec rails db:create db:migrate
```

### 4. Additional Production Considerations

1. **Use a reverse proxy** (nginx, Caddy, Traefik) in front of Rails for:
   - SSL/TLS termination
   - Load balancing
   - Static file serving
   - Rate limiting

2. **Set up SSL/TLS** certificates (use Let's Encrypt with Certbot)

3. **Configure backups** for PostgreSQL:
   ```bash
   # Backup
   docker-compose -f docker-compose.prod.yml exec db pg_dump -U postgres prompt_tracker_production > backup.sql

   # Restore
   docker-compose -f docker-compose.prod.yml exec -T db psql -U postgres prompt_tracker_production < backup.sql
   ```

4. **Monitor logs**:
   ```bash
   docker-compose -f docker-compose.prod.yml logs -f
   ```

5. **Set up monitoring** (Prometheus, Grafana, or similar)

6. **Configure log rotation** to prevent disk space issues

## Troubleshooting

For detailed troubleshooting, see [DOCKER_TROUBLESHOOTING.md](DOCKER_TROUBLESHOOTING.md).

### Quick Fixes

**Port Already in Use**
```yaml
# Edit docker-compose.yml
services:
  web:
    ports:
      - "3001:3000"  # Use port 3001 instead
```

**Database Issues**
```bash
docker-compose logs db
docker-compose exec web bundle exec rails db:reset
```

**Complete Reset**
```bash
docker-compose down -v
docker system prune -a
docker-compose up --build
```

**View Logs**
```bash
docker-compose logs -f        # All services
docker-compose logs -f web    # Web only
```

## Development Workflow

### Making Code Changes

The application code is mounted as a volume, so changes are reflected immediately:
- Ruby code changes require server restart: `docker-compose restart web`
- View changes are reflected immediately
- Gemfile changes require rebuild: `docker-compose build web`

### Installing New Gems

```bash
# Add gem to Gemfile, then:
docker-compose build web
docker-compose up
```

### Running Migrations

```bash
# Create migration
docker-compose exec web bundle exec rails generate migration MigrationName

# Run migration
docker-compose exec web bundle exec rails db:migrate
```

## Architecture

The Docker setup includes:

- **db**: PostgreSQL 16 database with persistent volume
- **redis**: Redis 7 for Sidekiq job queue
- **web**: Rails application server (Puma)
- **sidekiq**: Background job processor

All services are connected via a Docker network and can communicate using service names (e.g., `db`, `redis`).

## Next Steps

- Configure LLM API keys in environment variables
- Set up monitoring and logging
- Configure backups for PostgreSQL
- Set up CI/CD pipeline with Docker
