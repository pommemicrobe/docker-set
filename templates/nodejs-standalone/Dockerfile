FROM node:22-alpine

# Install system dependencies
RUN apk add --no-cache git curl

# Install PM2 globally
RUN npm install -g pm2

# Set working directory
WORKDIR /app

# Expose port
EXPOSE 3000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/health || curl -f http://localhost:3000/ || exit 1

# Install dependencies at runtime and start with PM2
CMD ["sh", "-c", "npm install && pm2-runtime start ecosystem.config.js"]
