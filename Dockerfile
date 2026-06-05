FROM node:22-alpine

WORKDIR /app

# Install only production dependencies first so this layer is cached
# unless package.json changes.
COPY package*.json ./
RUN npm install --omit=dev

COPY index.js ./

EXPOSE 4444

# Simple container health check hitting the app's only endpoint.
HEALTHCHECK --interval=5s --timeout=2s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:4444/ || exit 1

CMD ["node", "index.js"]
