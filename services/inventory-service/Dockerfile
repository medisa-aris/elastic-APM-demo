FROM golang:1.22-alpine AS builder

# CGO is required for go-sqlite3
RUN apk add --no-cache gcc musl-dev

WORKDIR /app

# Build context is the project root (see docker-compose.yml)
COPY services/inventory-service/go.mod services/inventory-service/go.sum* ./
RUN go mod download

COPY services/inventory-service/ .

RUN CGO_ENABLED=1 GOOS=linux go build -a -o /server ./cmd/server

# ---

FROM alpine:3.19

RUN apk add --no-cache ca-certificates wget

WORKDIR /app

COPY --from=builder /server /app/server

# Embed seed data from project root
COPY seed/seed-data.json /seed/seed-data.json

# Make /data writable by any UID (OpenShift runs as random non-root UID with GID 0)
RUN mkdir -p /data && \
    chgrp -R 0 /data /seed && \
    chmod -R g=u /data /seed

EXPOSE 8082

CMD ["/app/server"]
