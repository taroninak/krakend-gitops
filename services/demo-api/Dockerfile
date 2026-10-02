# demo-api: every upstream route behind the gateway, with the data it serves,
# as one versioned artifact.
FROM node:24-alpine

WORKDIR /app
ENV NODE_ENV=production

# Dependencies first: this layer is reused until package*.json changes.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src
COPY data ./data

# Numeric, not "node": Kubernetes can only verify runAsNonRoot against a uid.
USER 1000
EXPOSE 8080
CMD ["node", "src/server.js"]
