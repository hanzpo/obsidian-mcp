.PHONY: install start stop restart status logs logs-sync logs-mcp logs-caddy keygen update

install:
	@PROJECT_DIR=$$(pwd) && \
	OB_BIN=$$(command -v ob) && \
	NODE_BIN_DIR=$$(dirname $$(command -v node)) && \
	DOCKER_BIN=$$(command -v docker) && \
	for tmpl in systemd/*.template; do \
		unit=$$(basename $$tmpl .template); \
		sed -e "s|__PROJECT_DIR__|$$PROJECT_DIR|g" \
		    -e "s|__NODE_BIN_DIR__|$$NODE_BIN_DIR|g" \
		    -e "s|__OB_BIN__|$$OB_BIN|g" \
		    -e "s|__DOCKER_BIN__|$$DOCKER_BIN|g" \
		    $$tmpl > /etc/systemd/system/$$unit; \
	done
	systemctl daemon-reload
	systemctl enable obsidian-mcp.target

start:
	systemctl start obsidian-mcp.target

stop:
	systemctl stop obsidian-mcp.target

restart:
	systemctl restart obsidian-mcp.target

status:
	@systemctl status obsidian-sync.service --no-pager || true
	@echo ""
	@systemctl status obsidian-mcp.service --no-pager || true

logs:
	journalctl -u obsidian-sync -u obsidian-mcp -f

logs-sync:
	journalctl -u obsidian-sync -f

logs-mcp:
	docker compose logs -f mcp

logs-caddy:
	docker compose logs -f caddy

keygen:
	./keygen.sh

update:
	git pull
	$(MAKE) install
	systemctl restart obsidian-mcp.target
