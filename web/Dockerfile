# Build the Vite SPA and serve it as static files.
# Production backend/PowerSync URLs are baked into the bundle (see src/config.ts),
# so no build-time env is required.
FROM node:20-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-slim
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY server.mjs ./server.mjs
# Railway injects $PORT. The tiny server serves AASA as JSON, then falls back to index.html.
ENV PORT=3000
CMD ["node", "server.mjs"]
