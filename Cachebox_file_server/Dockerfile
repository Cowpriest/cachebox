# Use an official Node.js runtime as a base image
FROM node:20

# copy your service account key into the image
COPY cachebox-admin.json /secrets/cachebox-admin.json

# tell the Admin SDK where to find it
ENV GOOGLE_APPLICATION_CREDENTIALS=/secrets/cachebox-admin.json

# Create and set working directory
WORKDIR /usr/src/app

# Copy package files and install dependencies
COPY package*.json ./
RUN npm install

# Copy rest of the app files
COPY . .

# Expose the port your app runs on
EXPOSE 3000

# Start the server
CMD [ "node", "server.cjs" ]
