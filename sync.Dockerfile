FROM node:22-slim
RUN npm install -g obsidian-headless
WORKDIR /vault
CMD ["ob", "sync", "--continuous"]
