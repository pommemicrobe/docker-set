FROM node:22-alpine

# Install git and PM2 globally
RUN apk add --no-cache git
RUN npm install -g pm2

# Set the working directory
WORKDIR /app

# Expose the port
EXPOSE 3000

# Install dependencies at runtime and start with PM2
CMD ["sh", "-c", "npm install && pm2-runtime start ecosystem.config.js"]