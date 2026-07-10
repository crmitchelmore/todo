FROM node:20-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
COPY healthcheck.mjs ./
EXPOSE 6060
CMD ["npm", "start"]
