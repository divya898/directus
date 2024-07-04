# syntax=docker/dockerfile:1.4

####################################################################################################
## Build Packages

FROM node:18-alpine AS builder
WORKDIR /directus

ARG TARGETPLATFORM

ENV NODE_OPTIONS=--max-old-space-size=8192

# Platform-specific dependencies for linux/arm64
RUN if [ "$TARGETPLATFORM" = 'linux/arm64' ]; then \
      apk --no-cache add python3 build-base && \
      ln -sf /usr/bin/python3 /usr/bin/python; \
    fi

# Copy package files and prepare corepack
COPY package.json .
RUN corepack enable && corepack prepare

# Copy lock file and fetch dependencies
COPY pnpm-lock.yaml .
RUN pnpm fetch

# Copy project files
COPY . .

# Install dependencies and build the project
RUN pnpm install --recursive --offline --frozen-lockfile
RUN npm_config_workspace_concurrency=1 pnpm run build
RUN pnpm --filter directus deploy --prod dist

# Regenerate package.json with essential fields
RUN cd dist && \
    node -e 'const fs = require("fs"); const f = "package.json", {name, version, type, exports, bin} = require(`./${f}`), {packageManager} = require(`../${f}`); fs.writeFileSync(f, JSON.stringify({name, version, type, exports, bin, packageManager}, null, 2));' && \
    mkdir -p database extensions uploads

RUN ls -la /directus/
Run ls -la /directus/api/
####################################################################################################
## Create Production Image

FROM node:18-alpine AS runtime

# Install pm2 globally
RUN npm install --global pm2@5

# Switch to non-root user
USER node

WORKDIR /directus

# Expose application port
EXPOSE 8055

# Set environment variables
ENV \
    DB_CLIENT="sqlite3" \
    DB_FILENAME="/directus/database/database.sqlite" \
    NODE_ENV="production" \
    NPM_CONFIG_UPDATE_NOTIFIER="false"

# Copy the built application from the builder stage
COPY --from=builder --chown=node:node /directus/ecosystem.config.cjs /directus/
COPY --from=builder --chown=node:node /directus/dist /directus/

# Command to run the application
CMD [ "sh", "-c", "ls /directus && node cli.js bootstrap && pm2-runtime start ecosystem.config.cjs" ]
