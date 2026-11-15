# Shortcuts for ./setup.sh — run `make` to see them all.
# Windows without make? Use ./setup.sh <command> directly (same commands).

.DEFAULT_GOAL := help
.PHONY: help setup up down restart status logs info clean

s ?=

help: ## Show this help
	@echo "Usage: make <command>"
	@echo ""
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples: make up s=\"postgres redis\"   ·   make logs s=postgres"

setup: ## Interactive setup: pick services, configure, start
	@./setup.sh

up: ## Start your saved services (or only these: make up s="postgres redis")
	@./setup.sh $(if $(s),$(s),up)

down: ## Stop everything (data is kept)
	@./setup.sh down

restart: ## Restart your saved services
	@./setup.sh restart

status: ## Show what's running
	@./setup.sh status

logs: ## Follow logs (make logs s=postgres)
	@./setup.sh logs $(s)

info: ## Show URLs, connection strings and credentials
	@./setup.sh info

clean: ## Stop everything and DELETE all data volumes (asks first)
	@./setup.sh clean
