# Use the latest foundry image
# Base of this image is alpine linux 3.16
FROM ghcr.io/foundry-rs/foundry

# Install node and yarn
RUN apk add nodejs npm
RUN npm install --global yarn

# Copy our source code into the container
WORKDIR /premia-v3-contracts-private

ENTRYPOINT ["/bin/sh"]