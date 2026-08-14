FROM node:20-alpine AS builder

WORKDIR /app

COPY applications/app1/frontend/package*.json ./
RUN npm ci

COPY applications/app1/frontend/ .
RUN npm run build

FROM nginx:alpine

COPY --from=builder /app/build /usr/share/nginx/html
COPY docker/app1-frontend/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

# nginx:alpine ships no curl; wget is in the base image. Use 127.0.0.1, not
# localhost: the nginx conf binds IPv4 only and localhost resolves to ::1.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]