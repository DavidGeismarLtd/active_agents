# Docker Troubleshooting Guide

Common issues and solutions when running PromptTracker with Docker.

## Installation Issues

### Docker Not Installed

**Error**: `docker: command not found` or `docker-compose: command not found`

**Solution**:
1. Install Docker Desktop from https://www.docker.com/products/docker-desktop
2. Verify installation:
   ```bash
   docker --version
   docker-compose --version
   ```

### Docker Daemon Not Running

**Error**: `Cannot connect to the Docker daemon`

**Solution**:
1. Start Docker Desktop application
2. Wait for Docker to fully start (check system tray/menu bar)
3. Verify: `docker ps`

## Port Conflicts

### Port 3000 Already in Use

**Error**: `Bind for 0.0.0.0:3000 failed: port is already allocated`

**Solution 1**: Stop the conflicting service
```bash
# Find what's using port 3000
lsof -i :3000  # macOS/Linux
netstat -ano | findstr :3000  # Windows

# Kill the process or stop the service
```

**Solution 2**: Use a different port
```yaml
# Edit docker-compose.yml
services:
  web:
    ports:
      - "3001:3000"  # Use port 3001 instead
```

Then access at http://localhost:3001

### PostgreSQL Port 5432 Already in Use

**Solution**: Either stop local PostgreSQL or change the port mapping:
```yaml
services:
  db:
    ports:
      - "5433:5432"  # Use port 5433 externally
```

## Database Issues

### Database Connection Failed

**Error**: `could not connect to server: Connection refused`

**Solution**:
```bash
# Check if database is healthy
docker-compose ps

# View database logs
docker-compose logs db

# Restart database
docker-compose restart db

# If still failing, recreate
docker-compose down
docker-compose up -d db
```

### Database Does Not Exist

**Error**: `FATAL: database "prompt_tracker_development" does not exist`

**Solution**:
```bash
# Create and migrate database
docker-compose exec web bundle exec rails db:create db:migrate

# Or reset everything
docker-compose exec web bundle exec rails db:reset
```

### Migration Errors

**Error**: `PG::UndefinedTable` or migration failures

**Solution**:
```bash
# Check migration status
docker-compose exec web bundle exec rails db:migrate:status

# Rollback and retry
docker-compose exec web bundle exec rails db:rollback
docker-compose exec web bundle exec rails db:migrate

# Nuclear option - reset database
docker-compose exec web bundle exec rails db:drop db:create db:migrate
```

## Redis Issues

### Redis Connection Failed

**Error**: `Error connecting to Redis`

**Solution**:
```bash
# Check Redis health
docker-compose ps redis

# View Redis logs
docker-compose logs redis

# Test Redis connection
docker-compose exec redis redis-cli ping
# Should return: PONG

# Restart Redis
docker-compose restart redis
```

## Build Issues

### Gem Installation Failures

**Error**: `An error occurred while installing [gem]`

**Solution**:
```bash
# Clear bundle cache and rebuild
docker-compose down
docker-compose build --no-cache web
docker-compose up
```

### Dockerfile Changes Not Applied

**Solution**:
```bash
# Force rebuild without cache
docker-compose build --no-cache
docker-compose up
```

### Out of Disk Space

**Error**: `no space left on device`

**Solution**:
```bash
# Clean up Docker resources
docker system prune -a --volumes

# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune
```

## Runtime Issues

### Server Not Starting

**Error**: Server starts but crashes immediately

**Solution**:
```bash
# View detailed logs
docker-compose logs -f web

# Check for PID file issues
docker-compose exec web rm -f tmp/pids/server.pid
docker-compose restart web

# Check for missing dependencies
docker-compose exec web bundle install
docker-compose restart web
```

### Sidekiq Not Processing Jobs

**Solution**:
```bash
# Check Sidekiq logs
docker-compose logs -f sidekiq

# Verify Redis connection
docker-compose exec sidekiq bundle exec rails runner "puts Sidekiq.redis(&:ping)"

# Restart Sidekiq
docker-compose restart sidekiq
```

### Changes Not Reflected

**Issue**: Code changes not showing up

**Solution**:
1. Verify volume mounting in `docker-compose.yml`:
   ```yaml
   volumes:
     - .:/app  # Should be present
   ```

2. Restart the web server:
   ```bash
   docker-compose restart web
   ```

3. For Gemfile changes, rebuild:
   ```bash
   docker-compose build web
   docker-compose up
   ```

## Permission Issues

### Permission Denied Errors

**Error**: `Permission denied` when accessing files

**Solution**:
```bash
# Fix file permissions
sudo chown -R $USER:$USER .

# Or run with appropriate user in Dockerfile
# Add to Dockerfile:
# RUN useradd -m -u 1000 appuser
# USER appuser
```

## Performance Issues

### Slow Performance on macOS

**Issue**: Docker is slow on macOS

**Solutions**:
1. Use Docker Desktop's VirtioFS (Settings → Experimental Features)
2. Reduce volume mounts
3. Use named volumes for dependencies:
   ```yaml
   volumes:
     - bundle_cache:/usr/local/bundle
   ```

### High Memory Usage

**Solution**:
```bash
# Limit resources in Docker Desktop
# Settings → Resources → Advanced
# Reduce CPUs and Memory allocation

# Or in docker-compose.yml:
services:
  web:
    deploy:
      resources:
        limits:
          memory: 1G
```

## Complete Reset

### Nuclear Option - Start Fresh

When all else fails:

```bash
# Stop and remove everything
docker-compose down -v

# Remove all Docker resources
docker system prune -a --volumes

# Rebuild from scratch
docker-compose build --no-cache
docker-compose up
```

## Getting Help

If you're still stuck:

1. **Check logs**: `docker-compose logs -f`
2. **Check service status**: `docker-compose ps`
3. **Inspect containers**: `docker-compose exec web bash`
4. **Review documentation**: See DOCKER_SETUP.md
5. **Search issues**: Check GitHub issues for similar problems

## Useful Debugging Commands

```bash
# Enter web container shell
docker-compose exec web bash

# Check environment variables
docker-compose exec web env

# Test database connection
docker-compose exec web bundle exec rails runner "puts ActiveRecord::Base.connection.active?"

# Test Redis connection
docker-compose exec web bundle exec rails runner "puts Redis.new(url: ENV['REDIS_URL']).ping"

# View running processes
docker-compose exec web ps aux

# Check disk space
docker-compose exec web df -h

# View network configuration
docker network inspect prompt_tracker_default
```

