# Docker Quick Start Guide

Get PromptTracker running in 3 simple steps!

## Prerequisites

- Docker Desktop installed ([Download here](https://www.docker.com/products/docker-desktop))

## Steps

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd prompt_tracker
```

### 2. Start Everything

```bash
docker-compose up --build
```

This single command will:
- ✅ Build the Docker image
- ✅ Start PostgreSQL database
- ✅ Start Redis server
- ✅ Start Rails web server
- ✅ Start Sidekiq worker
- ✅ Run database migrations automatically

### 3. Open Your Browser

Navigate to: **http://localhost:3000**

That's it! 🎉

## Common Commands

### Using Make (Easier!)

```bash
make help            # Show all available commands
make down            # Stop all services
make logs            # View logs
make console         # Run Rails console
make test            # Run tests
make db-reset        # Reset database
```

### Using Docker Compose

```bash
# Stop all services
docker-compose down

# View logs
docker-compose logs -f

# Run Rails console
docker-compose exec web bundle exec rails console

# Run tests
docker-compose exec web bundle exec rspec

# Reset database
docker-compose exec web bundle exec rails db:reset
```

## Troubleshooting

**Port already in use?**
```bash
# Edit docker-compose.yml and change the port mapping:
ports:
  - "3001:3000"  # Use 3001 instead of 3000
```

**Need to rebuild?**
```bash
docker-compose down
docker-compose build --no-cache
docker-compose up
```

**Complete reset?**
```bash
docker-compose down -v  # Removes all data
docker-compose up --build
```

## Next Steps

- See [DOCKER_SETUP.md](DOCKER_SETUP.md) for detailed documentation
- Configure LLM API keys in `.env` file (copy from `.env.example`)
- Read [README.md](README.md) for feature documentation
