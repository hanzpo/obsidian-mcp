.PHONY: install build start stop restart status logs logs-sync logs-mcp logs-caddy keygen update

OS := $(shell uname -s)

# Detect vault names from vaults/ subdirectories
VAULT_NAMES := $(notdir $(wildcard vaults/*/))
SYNC_SERVICES := $(foreach name,$(VAULT_NAMES),obsidian-sync-$(name).service)

build:
	npm ci --silent
	npm run build --silent

install: build
ifeq ($(OS),Darwin)
	@echo "On macOS, run sudo ./setup.sh to install services."
else
	mkdir -p /etc/systemd/system
	@PROJECT_DIR=$$(pwd) && \
	OB_BIN=$$(command -v ob) && \
	NODE_BIN=$$(command -v node) && \
	NODE_BIN_DIR=$$(dirname $$NODE_BIN) && \
	CADDY_BIN=$$(command -v caddy) && \
	SYNC_SERVICES="$(SYNC_SERVICES)" && \
	for name in $(VAULT_NAMES); do \
		sed -e "s|__VAULT_NAME__|$$name|g" \
		    -e "s|__VAULT_DIR__|$$PROJECT_DIR/vaults/$$name|g" \
		    -e "s|__NODE_BIN_DIR__|$$NODE_BIN_DIR|g" \
		    -e "s|__OB_BIN__|$$OB_BIN|g" \
		    systemd/obsidian-sync.service.template \
		    > /etc/systemd/system/obsidian-sync-$$name.service; \
	done && \
	for tmpl in systemd/obsidian-mcp.service.template systemd/caddy.service.template systemd/obsidian-mcp.target.template; do \
		unit=$$(basename $$tmpl .template); \
		sed -e "s|__PROJECT_DIR__|$$PROJECT_DIR|g" \
		    -e "s|__NODE_BIN_DIR__|$$NODE_BIN_DIR|g" \
		    -e "s|__NODE_BIN__|$$NODE_BIN|g" \
		    -e "s|__OB_BIN__|$$OB_BIN|g" \
		    -e "s|__CADDY_BIN__|$$CADDY_BIN|g" \
		    -e "s|__SYNC_SERVICES__|$$SYNC_SERVICES|g" \
		    $$tmpl > /etc/systemd/system/$$unit; \
	done
	systemctl daemon-reload
	systemctl enable obsidian-mcp.target
endif

ifeq ($(OS),Darwin)
start:
	launchctl bootstrap system ~/Library/LaunchDaemons/com.obsidian-mcp.server.plist 2>/dev/null || true
	launchctl bootstrap system ~/Library/LaunchDaemons/com.obsidian-mcp.caddy.plist 2>/dev/null || true
	@for name in $(VAULT_NAMES); do \
		launchctl bootstrap system ~/Library/LaunchDaemons/com.obsidian-mcp.sync-$$name.plist 2>/dev/null || true; \
	done

stop:
	launchctl bootout system ~/Library/LaunchDaemons/com.obsidian-mcp.server.plist 2>/dev/null || true
	launchctl bootout system ~/Library/LaunchDaemons/com.obsidian-mcp.caddy.plist 2>/dev/null || true
	@for name in $(VAULT_NAMES); do \
		launchctl bootout system ~/Library/LaunchDaemons/com.obsidian-mcp.sync-$$name.plist 2>/dev/null || true; \
	done

restart: stop start

status:
	@launchctl print system/com.obsidian-mcp.server 2>/dev/null || echo "MCP server: not running"
	@launchctl print system/com.obsidian-mcp.caddy 2>/dev/null || echo "Caddy: not running"
	@for name in $(VAULT_NAMES); do \
		launchctl print system/com.obsidian-mcp.sync-$$name 2>/dev/null || echo "Sync $$name: not running"; \
	done

logs:
	tail -f /tmp/obsidian-mcp.log /tmp/obsidian-caddy.log /tmp/obsidian-sync-*.log

logs-sync:
	tail -f /tmp/obsidian-sync-*.log

logs-mcp:
	tail -f /tmp/obsidian-mcp.log

logs-caddy:
	tail -f /tmp/obsidian-caddy.log

else
start:
	systemctl start obsidian-mcp.target

stop:
	systemctl stop obsidian-mcp.target

restart:
	systemctl restart obsidian-mcp.target

status:
	@for svc in $(SYNC_SERVICES); do \
		systemctl status $$svc --no-pager || true; \
		echo ""; \
	done
	@systemctl status obsidian-mcp.service --no-pager || true
	@echo ""
	@systemctl status caddy.service --no-pager || true

logs:
	journalctl -u 'obsidian-sync-*' -u obsidian-mcp -u caddy -f

logs-sync:
	journalctl -u 'obsidian-sync-*' -f

logs-mcp:
	journalctl -u obsidian-mcp -f

logs-caddy:
	journalctl -u caddy -f
endif

keygen:
	./keygen.sh

update:
	git pull
	$(MAKE) install
ifeq ($(OS),Darwin)
	$(MAKE) restart
else
	systemctl restart obsidian-mcp.target
endif
