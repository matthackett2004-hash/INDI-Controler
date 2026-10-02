SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: help env build up down restart logs shell drivers status host-setup

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

env: ## Create .env from .env.example (won't overwrite)
	@test -f .env && echo ".env already exists" || (cp .env.example .env && echo "Created .env; edit INDI_DRIVERS")

build: ## Build the controller image
	docker compose build

up: ## Start the controller in the background
	docker compose up -d

down: ## Stop the controller
	docker compose down

restart: ## Restart (picks up .env changes)
	docker compose up -d --force-recreate

logs: ## Tail controller logs
	docker compose logs -f

shell: ## Open a shell in the running container
	docker compose exec indi-controller bash

drivers: ## List INDI driver binaries available in the image
	@docker run --rm --entrypoint bash indi-controller:latest -c 'ls /usr/bin/indi_* | xargs -n1 basename | grep -vE "^indi_(getprop|setprop|eval|web)$$"' | column

status: ## Show container health and listening ports
	@docker compose ps
	@for p in $${INDI_HOST_PORT:-7624} $${PHD2_HOST_PORT:-4400}; do \
		(exec 3<>/dev/tcp/127.0.0.1/$$p) 2>/dev/null && echo "port $$p: open" || echo "port $$p: closed"; done

host-setup: ## Install udev rules on this host (needs sudo, run after build)
	sudo ./host/install-host.sh
