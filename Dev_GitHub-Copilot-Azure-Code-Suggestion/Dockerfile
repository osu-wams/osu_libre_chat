# LibreChat Dockerfile for Azure Container Apps
FROM node:20-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git python3 make g++

# Clone LibreChat repository
ARG LIBRECHAT_VERSION=v0.7.6
RUN git clone --branch ${LIBRECHAT_VERSION} --depth 1 https://github.com/danny-avila/LibreChat.git .

# Install dependencies
RUN npm ci

# Build the application
RUN npm run frontend

# Production stage
FROM node:20-alpine

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache curl

# Copy built application from builder
COPY --from=builder /app .

# Create necessary directories
RUN mkdir -p /app/client/public/images

# Expose port
EXPOSE 3080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3080/api/health || exit 1

# Start the application
CMD ["npm", "run", "backend"]
