# Build the Vite SPA and serve it as static files.
# Production backend/PowerSync URLs are baked into the bundle (see src/config.ts),
# so no build-time env is required.
FROM node:20-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG VITE_BACKEND_URL
ARG VITE_POWERSYNC_URL
ARG VITE_SENTRY_DSN
ARG VITE_SENTRY_ENVIRONMENT
ENV VITE_BACKEND_URL=${VITE_BACKEND_URL}
ENV VITE_POWERSYNC_URL=${VITE_POWERSYNC_URL}
ENV VITE_SENTRY_DSN=${VITE_SENTRY_DSN}
ENV VITE_SENTRY_ENVIRONMENT=${VITE_SENTRY_ENVIRONMENT}
RUN npm run build

FROM node:20-slim
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY server.mjs ./server.mjs
COPY healthcheck.mjs ./healthcheck.mjs
# Railway injects $PORT. The tiny server serves AASA as JSON, then falls back to index.html.
ENV PORT=3000
CMD ["node", "server.mjs"]
