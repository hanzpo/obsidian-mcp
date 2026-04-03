.PHONY: install start stop restart status logs logs-sync logs-mcp logs-caddy keygen update

install:
	cp systemd/* /etc/systemd/system/
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
	systemctl restart obsidian-mcp.target
