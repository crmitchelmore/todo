FROM node:25-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
EXPOSE 6060
CMD ["npm", "start"]
