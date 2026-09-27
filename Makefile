SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ENV_FILE ?= $(CURDIR)/.env
export ENV_FILE

.PHONY: help versions validate cert external-up external-up-inference external-health external-down build push deploy fault-test alert-test dind-test rollback ps
help:
	@echo "versions               print independent content versions for every image"
	@echo "validate               validate shell, Compose and Swarm YAML"
	@echo "cert                   generate a local self-signed TLS certificate"
	@echo "external-up            start PostgreSQL and MinIO outside Swarm"
	@echo "external-up-inference  also start external medical-scribe mock"
	@echo "build                  build four local application/infra images"
	@echo "push                   authenticate and push four images to the configured registry"
	@echo "deploy                 label nodes, create missing secrets and deploy"
	@echo "fault-test             restart, rolling update, rollback, node drain"
	@echo "alert-test             send a deliberate DOWN event to Kuma"
	@echo "dind-test              isolated three-daemon Swarm integration test"
	@echo "rollback COMPONENT=all rollback all or backend/frontend/gateway"

versions:
	@./scripts/image-versions.sh

validate:
	./scripts/validate.sh

cert:
	./scripts/generate-local-cert.sh

external-up:
	docker compose --env-file "$(ENV_FILE)" -f external-local/compose.yml up -d --wait postgres minio minio-init

external-up-inference:
	docker compose --env-file "$(ENV_FILE)" -f external-local/compose.yml --profile inference up -d --wait

external-health:
	./scripts/external-health.sh

external-down:
	docker compose --env-file "$(ENV_FILE)" -f external-local/compose.yml --profile inference down

build:
	./scripts/build-local.sh

push:
	./scripts/push-images.sh

deploy:
	./scripts/deploy.sh

fault-test:
	./scripts/fault-test.sh

alert-test:
	./scripts/uptime-alert-test.sh

dind-test:
	./scripts/lab/dind-test.sh

rollback:
	./scripts/rollback.sh "$(or $(COMPONENT),all)"

ps:
	@source "$(ENV_FILE)" && docker stack services "$$STACK_NAME"
