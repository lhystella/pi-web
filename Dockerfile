# syntax=docker/dockerfile:1

# ---------- Build stage ----------
# Build the Next.js production bundle. We use the full node image here so that
# native/optional deps and the pi SDK build correctly.
FROM node:24-slim AS builder

WORKDIR /app

# Install dependencies first (better layer caching).
COPY package.json package-lock.json ./
RUN npm ci

# Copy the rest of the source and build.
COPY . .
# `next build` writes to .next/ — this is the release build, not dev.
RUN npm run build


# ---------- Runtime stage ----------
FROM node:24-slim AS runner

# The pi agent runs real tools (bash, git, file edits) in-process, so make sure
# a usable shell + git + common utilities are available inside the container.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
        curl \
        ripgrep \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production \
    PORT=30141 \
    PI_WEB_NO_OPEN=1

WORKDIR /app

# Bring over the built app + everything needed to run `next start`.
COPY --from=builder /app/package.json /app/package-lock.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/next.config.ts ./next.config.ts
COPY --from=builder /app/bin ./bin

EXPOSE 30141

# --hostname 0.0.0.0 so the server is reachable from outside the container.
# (We pass it explicitly because Docker sets HOSTNAME to the container id, which
# the launcher would otherwise hand to `next start -H`.)
CMD ["node", "bin/pi-web.js", "--hostname", "0.0.0.0", "--no-open"]
