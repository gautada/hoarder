ARG ALPINE_VERSION=latest

################# Base Builder ##############
FROM node:22-alpine AS base

RUN /sbin/apk add --no-cache git pnpm

ARG HOARDER_VERSION="0.22.0"
 
WORKDIR /
RUN git config --global advice.detachedHead false
RUN git clone --branch "v$HOARDER_VERSION" https://github.com/hoarder-app/hoarder.git app
WORKDIR /app

# ENV PNPM_HOME="/pnpm"
# ENV PATH="$PNPM_HOME:$PATH"

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
 

################# The All-in-one builder ##############

FROM node:22-alpine AS aio_builder
LABEL org.opencontainers.image.source="https://github.com/hoarder-app/hoarder"
WORKDIR /app

ARG SERVER_VERSION=nightly
ENV SERVER_VERSION=${SERVER_VERSION}

USER root

ENV PORT 3000
ENV HOSTNAME "0.0.0.0"
EXPOSE 3000

######################
# Install runtime deps
######################
RUN apk add --no-cache monolith yt-dlp

######################
# Prepare the web app
######################

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

COPY --from=base --chown=node:node /app/apps/web/.next/standalone ./
COPY --from=base /app/apps/web/public ./apps/web/public
COPY --from=base /db_migrations /db_migrations

# Set the correct permission for prerender cache
RUN mkdir -p ./apps/web/.next && chown node:node ./apps/web/.next

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=base --chown=node:node /app/apps/web/.next/static ./apps/web/.next/static

######################
# Prepare the workers app
######################
COPY --from=base /prod/workers /app/apps/workers
RUN corepack enable && corepack pack

# ENTRYPOINT ["/init"]
