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
RUN npm install -g serve@14
COPY --from=build /app/dist ./dist
# Railway injects $PORT. `serve -s` rewrites unknown routes to index.html (SPA).
ENV PORT=3000
CMD ["sh", "-c", "serve -s dist -l ${PORT:-3000}"]
