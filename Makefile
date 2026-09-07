.PHONY: bootstrap preflight test-unit test-relay test-streaming tailscale-status wecom-status pull up logs down config \
	openclaw-install openclaw-host-status openclaw-host-power openclaw-configure openclaw-preflight \
	openclaw-gateway-install openclaw-start openclaw-stop openclaw-restart openclaw-status \
	openclaw-audit openclaw-model-gate openclaw-search-gate openclaw-sandbox-gate \
	openclaw-relay-gate openclaw-image-gate openclaw-accept openclaw-weixin-login openclaw-backup openclaw-rollback \
	openclaw-self-heal openclaw-self-heal-install

bootstrap:
	@./scripts/bootstrap.sh

preflight:
	@./scripts/preflight.sh

test-unit:
	@./scripts/tests/dotenv.test.sh
	@PYTHONPATH=./runtime python3 -m unittest runtime/test_init_config.py
	@node --test ./scripts/tests/openclaw-relay-gate.test.mjs

test-relay:
	@./scripts/test-relay.sh

test-streaming:
	@./scripts/test-streaming.sh

tailscale-status:
	@./scripts/tailscale-status.sh

wecom-status:
	@./scripts/wecom-status.sh

pull:
	@./scripts/compose.sh pull

up:
	@./scripts/start.sh

logs:
	@./scripts/logs.sh

down:
	@./scripts/stop.sh

config:
	@./scripts/compose.sh --env-file .env config

openclaw-install:
	@./scripts/openclaw-install.sh

openclaw-host-status:
	@./scripts/openclaw-host-setup.sh status

openclaw-host-power:
	@./scripts/openclaw-host-setup.sh power

openclaw-configure:
	@./scripts/openclaw-configure.sh

openclaw-preflight:
	@./scripts/openclaw-preflight.sh

openclaw-gateway-install:
	@./scripts/openclaw-gateway.sh install

openclaw-start:
	@./scripts/openclaw-gateway.sh start

openclaw-stop:
	@./scripts/openclaw-gateway.sh stop

openclaw-restart:
	@./scripts/openclaw-gateway.sh restart

openclaw-status:
	@./scripts/openclaw-status.sh

openclaw-self-heal:
	@./scripts/openclaw-self-heal.sh

openclaw-self-heal-install:
	@./scripts/openclaw-self-heal-install.sh

openclaw-audit:
	@./scripts/openclaw-audit.sh

openclaw-model-gate:
	@./scripts/openclaw-model-gate.sh

openclaw-relay-gate:
	@./scripts/openclaw-relay-gate.sh

openclaw-search-gate:
	@./scripts/openclaw-search-gate.sh

openclaw-sandbox-gate:
	@./scripts/openclaw-sandbox-gate.sh

openclaw-image-gate:
	@./scripts/openclaw-image-gate.sh

openclaw-accept:
	@./scripts/openclaw-accept.sh

openclaw-weixin-login:
	@./scripts/openclaw-weixin-login.sh

openclaw-backup:
	@./scripts/openclaw-backup.sh

openclaw-rollback:
	@./scripts/openclaw-rollback.sh
