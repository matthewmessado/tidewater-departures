# syntax=docker/dockerfile:1

# ---------- Stage 1: install production dependencies ----------
# This stage has npm's cache, the lockfile and build noise in it. None of
# that is copied into the final image - only the finished node_modules tree.
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ---------- Stage 2: minimal runtime image ----------
FROM node:22-alpine AS runtime

# Set by the pipeline to the git commit SHA; surfaced by GET /health so we
# can prove which build is live after a deploy or a rollback.
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION \
    NODE_ENV=production \
    PORT=8080

WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# Run as the unprivileged user that ships with the node image.
USER node
EXPOSE 8080

# Docker-level liveness check (busybox wget is already in alpine).
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health >/dev/null || exit 1

CMD ["node", "src/server.js"]
