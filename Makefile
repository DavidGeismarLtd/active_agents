.PHONY: help build up down restart logs shell console test db-reset db-migrate clean

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build Docker images
	docker-compose build

up: ## Start all services
	docker-compose up

up-d: ## Start all services in detached mode
	docker-compose up -d

down: ## Stop all services
	docker-compose down

down-v: ## Stop all services and remove volumes
	docker-compose down -v

restart: ## Restart all services
	docker-compose restart

logs: ## Show logs from all services
	docker-compose logs -f

logs-web: ## Show logs from web service
	docker-compose logs -f web

logs-sidekiq: ## Show logs from sidekiq service
	docker-compose logs -f sidekiq

shell: ## Open a shell in the web container
	docker-compose exec web bash

console: ## Open Rails console
	docker-compose exec web bundle exec rails console

test: ## Run all tests
	docker-compose exec web bin/test_all

rspec: ## Run RSpec tests
	docker-compose exec web bundle exec rspec

db-migrate: ## Run database migrations
	docker-compose exec web bundle exec rails db:migrate

db-reset: ## Reset database
	docker-compose exec web bundle exec rails db:reset

db-seed: ## Seed database
	docker-compose exec web bundle exec rails db:seed

clean: ## Clean up Docker resources
	docker-compose down -v
	docker system prune -f

rebuild: ## Rebuild and restart all services
	docker-compose down
	docker-compose build --no-cache
	docker-compose up

