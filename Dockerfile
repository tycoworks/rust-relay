# Use the official Rust image as a builder
FROM rust:1.76-slim-bullseye as builder

# Create a new empty shell project
WORKDIR /usr/src/rust-relay
COPY . .

# Build the application
RUN cargo build --release

# Create a new stage with a minimal image
FROM debian:bullseye-slim

# Install OpenSSL - it's needed by the Rust binary
RUN apt-get update && \
    apt-get install -y ca-certificates libssl1.1 && \
    rm -rf /var/lib/apt/lists/*

# Copy the binary from builder
COPY --from=builder /usr/src/rust-relay/target/release/rust-relay /usr/local/bin/rust-relay

# Set the working directory
WORKDIR /usr/local/bin

# Run the binary
CMD ["rust-relay"] 