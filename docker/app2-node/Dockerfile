FROM node:20-alpine

WORKDIR /app

ENV NODE_ENV=production

COPY applications/app2/src/package*.json ./
RUN npm ci --omit=dev

COPY applications/app2/src/ .

RUN addgroup -g 1001 -S nodejs \
    && adduser -S nodejs -u 1001 \
    && chown -R nodejs:nodejs /app
USER nodejs

EXPOSE 3000

# node:20-alpine ships no curl; Node 20 global fetch does the probe.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.status===200?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]