FROM node:26-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
EXPOSE 6060
CMD ["npm", "start"]
