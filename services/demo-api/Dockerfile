# The upstream services behind the gateway. Code only — the data each instance
# serves is mounted at runtime (DATA_FILE), so changing data needs no rebuild.
FROM node:24-alpine

WORKDIR /app
ENV NODE_ENV=production

# Dependencies first: this layer is reused until package*.json changes.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src

# Numeric, not "node": Kubernetes can only verify runAsNonRoot against a uid.
USER 1000
EXPOSE 8080
CMD ["node", "src/server.js"]
