.DEFAULT_GOAL := help

.PHONY: help build keygen \
	quickstart quickstart-stop quickstart-status quickstart-logs \
	prod-install prod-up prod-down prod-restart prod-status prod-logs prod-update \
	install start stop restart status logs logs-sync logs-mcp logs-caddy update

OS := $(shell uname -s)
SERVICE ?= all

help:
	@echo "obsidian-mcp commands"
	@echo ""
	@echo "Quickstart"
	@echo "  make quickstart         Start or rerun the fast remote setup flow"
	@echo "  make quickstart-status  Show quickstart background processes"
	@echo "  make quickstart-logs    Tail quickstart logs"
	@echo "  make quickstart-stop    Stop quickstart background processes"
	@echo ""
	@echo "Production"
	@echo "  make prod-install       Run the production setup flow"
	@echo "  make prod-up            Start production services"
	@echo "  make prod-down          Stop production services"
	@echo "  make prod-restart       Restart production services"
	@echo "  make prod-status        Show production service status"
	@echo "  make prod-logs          Tail production logs (SERVICE=all|sync|mcp|caddy)"
	@echo "  make prod-update        Pull latest changes and rerun production setup"
	@echo ""
	@echo "Other"
	@echo "  make build             Install deps and compile TypeScript"
	@echo "  make keygen            Generate or rotate the API key"

build:
	npm ci --silent
	npm run build --silent

keygen:
	./keygen.sh

quickstart:
	PATH="$(HOME)/.local/bin:$$PATH" ./setup.sh --quickstart

quickstart-stop:
	@for pidfile in .obsidian-mcp/pids/*.pid; do \
		[ -f "$$pidfile" ] || continue; \
		pid=$$(cat "$$pidfile" 2>/dev/null || true); \
		if [ -n "$$pid" ] && kill -0 "$$pid" 2>/dev/null; then \
			kill "$$pid" 2>/dev/null || true; \
		fi; \
		rm -f "$$pidfile"; \
	done

quickstart-status:
	@for pidfile in .obsidian-mcp/pids/*.pid; do \
		[ -f "$$pidfile" ] || continue; \
		name=$$(basename "$$pidfile" .pid); \
		pid=$$(cat "$$pidfile" 2>/dev/null || true); \
		if [ -n "$$pid" ] && kill -0 "$$pid" 2>/dev/null; then \
			echo "$$name: running (pid $$pid)"; \
		else \
			echo "$$name: stopped"; \
		fi; \
	done

quickstart-logs:
	tail -f .obsidian-mcp/logs/*.log

prod-install:
	sudo ./setup.sh --production

ifeq ($(OS),Darwin)
prod-up:
	sudo launchctl bootstrap system /Library/LaunchDaemons/com.obsidian-mcp.server.plist 2>/dev/null || true
	sudo launchctl bootstrap system /Library/LaunchDaemons/com.obsidian-mcp.caddy.plist 2>/dev/null || true
	@for plist in /Library/LaunchDaemons/com.obsidian-mcp.sync-*.plist; do \
		[ -f "$$plist" ] || continue; \
		sudo launchctl bootstrap system "$$plist" 2>/dev/null || true; \
	done

prod-down:
	sudo launchctl bootout system /Library/LaunchDaemons/com.obsidian-mcp.server.plist 2>/dev/null || true
	sudo launchctl bootout system /Library/LaunchDaemons/com.obsidian-mcp.caddy.plist 2>/dev/null || true
	@for plist in /Library/LaunchDaemons/com.obsidian-mcp.sync-*.plist; do \
		[ -f "$$plist" ] || continue; \
		sudo launchctl bootout system "$$plist" 2>/dev/null || true; \
	done

prod-restart: prod-down prod-up

prod-status:
	@sudo launchctl print system/com.obsidian-mcp.server 2>/dev/null || echo "MCP server: not running"
	@sudo launchctl print system/com.obsidian-mcp.caddy 2>/dev/null || echo "Caddy: not running"
	@for label in $$(find /Library/LaunchDaemons -maxdepth 1 -name 'com.obsidian-mcp.sync-*.plist' -exec basename {} .plist \; 2>/dev/null); do \
		sudo launchctl print system/$$label 2>/dev/null || echo "$$label: not running"; \
	done

prod-logs:
	@case "$(SERVICE)" in \
		all) tail -f /tmp/obsidian-mcp.log /tmp/obsidian-caddy.log /tmp/obsidian-sync-*.log ;; \
		sync) tail -f /tmp/obsidian-sync-*.log ;; \
		mcp) tail -f /tmp/obsidian-mcp.log ;; \
		caddy) tail -f /tmp/obsidian-caddy.log ;; \
		*) echo "Unknown SERVICE=$(SERVICE). Use all, sync, mcp, or caddy."; exit 1 ;; \
	esac
else
prod-up:
	sudo systemctl start obsidian-mcp.target

prod-down:
	sudo systemctl stop obsidian-mcp.target

prod-restart:
	sudo systemctl restart obsidian-mcp.target

prod-status:
	@for svc in $$(systemctl list-unit-files 'obsidian-sync-*.service' --no-legend 2>/dev/null | awk '{print $$1}'); do \
		sudo systemctl status "$$svc" --no-pager || true; \
		echo ""; \
	done
	@sudo systemctl status obsidian-mcp.service --no-pager || true
	@echo ""
	@sudo systemctl status caddy.service --no-pager || true

prod-logs:
	@case "$(SERVICE)" in \
		all) sudo journalctl -u 'obsidian-sync-*' -u obsidian-mcp -u caddy -f ;; \
		sync) sudo journalctl -u 'obsidian-sync-*' -f ;; \
		mcp) sudo journalctl -u obsidian-mcp -f ;; \
		caddy) sudo journalctl -u caddy -f ;; \
		*) echo "Unknown SERVICE=$(SERVICE). Use all, sync, mcp, or caddy."; exit 1 ;; \
	esac
endif

prod-update:
	git pull
	sudo ./setup.sh --production

# Compatibility aliases
install: prod-install
start: prod-up
stop: prod-down
restart: prod-restart
status: prod-status
logs: prod-logs
logs-sync:
	$(MAKE) prod-logs SERVICE=sync
logs-mcp:
	$(MAKE) prod-logs SERVICE=mcp
logs-caddy:
	$(MAKE) prod-logs SERVICE=caddy
update: prod-update
