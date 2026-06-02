FROM node:20-slim
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
EXPOSE 6060
CMD ["npm", "start"]
