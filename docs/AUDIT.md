# Source audit

Audited on 2026-09-10. Runtime code was treated as authoritative.

## `../overtone`

- React/Vite frontend, login and `/admin` are already implemented; no application rewrite is needed.
- The browser uses relative `/api/*` URLs and API contract version `1`.
- Backend image runs NestJS on port 3000. Health endpoint: `/api/health`.
- The same backend image runs the BullMQ worker with `node dist/worker/main.js`.
- API staging uses `RECORDINGS_DIR`; one API replica therefore needs node-local persistence and fixed placement.
- Backend startup applies PostgreSQL migrations. PostgreSQL must use direct/session-pooled connections because the application uses session advisory locks.
- The frontend now owns a self-contained production image: Vite assets are served by an unprivileged Nginx static origin on port 8080, with `/frontend-health` and `/tmp` as its only writable runtime path. It needs no shared volume, so identical replicas can run on separate Swarm workers. Infra only references this image; the TLS gateway remains a separate container.

## `../medical-scribe`

- gRPC listens on port 50051 and the service needs its own PostgreSQL connection plus S3 access.
- It stays outside Swarm. `external-local/compose.yml` can start its existing mock image for connectivity tests.
- The current mock accepts pipeline calls but may still return `MODEL_LOAD_FAILED` for model-dependent full-pipeline work; this is an application fixture limitation, not hidden by the infrastructure smoke test.

## `../local-stack`

- Established gateway behavior was retained: 1025 MiB request limit, 35-minute upstream timeout, exact `/admin` SPA route, `/admin/*` 404 behavior and IP filtering for both page/API.
- PostgreSQL/MinIO volume names in this repository are new and are never deleted by the supplied commands.
- Redis moved into Swarm as required; PostgreSQL, MinIO and inference did not.

The frontend runtime contract is owned by `../overtone`; this repository consumes it without duplicating application build or server files.
