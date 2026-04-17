.DEFAULT_GOAL := help

STACKS := authentik unify-networking home-assistant portainer nginx-proxy-manager traefik-revproxy wgweiser n8n beszel immich zigbee2mqtt

compose-file = $(firstword \
  $(wildcard $(1)/compose.yml) \
  $(wildcard $(1)/docker-compose.yml) \
  $(wildcard $(1)/docker-compose.yaml))

.PHONY: help ps up-all down-all $(foreach s,$(STACKS),up-$(s) down-$(s) logs-$(s))

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Global:"
	@echo "  ps          Show status of all running compose projects"
	@echo "  up-all      Start all stacks"
	@echo "  down-all    Stop all stacks"
	@echo ""
	@echo "Per-stack (replace <stack> with one of: $(STACKS)):"
	@echo "  up-<stack>    Start stack"
	@echo "  down-<stack>  Stop stack"
	@echo "  logs-<stack>  Follow logs"

ps:
	docker compose ls

up-all:
	@$(foreach s,$(STACKS),$(MAKE) up-$(s);)

down-all:
	@$(foreach s,$(STACKS),$(MAKE) down-$(s);)

define stack-targets
up-$(1):
	docker compose -f $(call compose-file,$(1)) up -d

down-$(1):
	docker compose -f $(call compose-file,$(1)) down

logs-$(1):
	docker compose -f $(call compose-file,$(1)) logs -f
endef

$(foreach s,$(STACKS),$(eval $(call stack-targets,$(s))))
