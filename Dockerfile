# Use the latest foundry image
FROM ghcr.io/foundry-rs/foundry

# Copy our source code into the container
WORKDIR /app

COPY . .