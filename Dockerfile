FROM node:18-alpine

WORKDIR /app

# Copy package files from server directory
COPY server/package*.json ./

# Install dependencies (including dev dependencies for build)
RUN npm install

# Copy server source code
COPY server/ .

# Build TypeScript
RUN npm run build

# Expose port
EXPOSE 3000

# Start server
CMD ["npm", "start"]

