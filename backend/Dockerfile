# ---------- Stage 1: Build ----------
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./

RUN npm install


COPY . .


# ---------- Stage 2: Production ----------
FROM node:20-alpine AS runner

WORKDIR /app

RUN addgroup -S appgroup && adduser -S appuser -G appgroup


COPY --from=builder /app /app


RUN chown -R appuser:appgroup /app

USER appuser
EXPOSE 4000


CMD ["node", "server.js"]
