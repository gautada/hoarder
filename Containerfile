ARG ALPINE_VERSION=latest

################# Base Builder ##############
FROM node:22-alpine AS base

# RUN /sbin/apk add --no-cache pnpm

ARG HOARDER_VERSION="0.22.0"
 
WORKDIR /
RUN git config --global advice.detachedHead false
RUN git clone --branch "v$HOMEPAGE_VERSION" https://github.com/hoarder-app/hoarder.git app
WORKDIR /app

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# https://github.com/hoarder-app/hoarder/issues/967
RUN npm install -g corepack@0.31.0 && corepack enable

# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat make g++ py3-pip linux-headers


ENV NEXT_TELEMETRY_DISABLED 1
ENV PUPPETEER_SKIP_DOWNLOAD true
RUN pnpm install --frozen-lockfile






# Build the db migration script
RUN cd packages/db && \
    pnpm dlx @vercel/ncc build migrate.ts -o /db_migrations && \
    cp -R drizzle /db_migrations


# Compile the web app
RUN (cd apps/web && pnpm exec next build --experimental-build-mode compile)

# Build the worker code
RUN pnpm deploy --node-linker=isolated --filter @hoarder/workers --prod /prod/workers

# Build the cli
RUN (cd apps/cli && pnpm build)
 

