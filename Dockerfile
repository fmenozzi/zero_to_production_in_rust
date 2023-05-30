FROM lukemathwalker/cargo-chef:latest-rust-1.69.0 AS chef
# Let's switch our working directory to `app` (equivalent to `cd app`)
# The `app` folder will be created for us by Docker in case it does not
# exist already.
WORKDIR /app
RUN apt update && apt install lld clang -y

FROM chef AS planner
COPY . .
# Compute a lock-like file for our project.
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
# Build our project dependencies, not our application.
RUN cargo chef cook --release --recipe-path recipe.json
# Up to this point, if our dependency tree stays the same, all layers
# should be cached.
COPY . .

# Set environment variables.
#
# SQLX_OFFLINE forces sqlx to look at the saved metadata file instead of
# trying to query a live database.
ENV SQLX_OFFLINE true

# Build the binary using the release profile.
RUN cargo build --release --bin zero2prod

# Runtime stage. Use debian slim, since we don't need the Rust toolchain for
# actually running the binary.
FROM debian:bullseye-slim AS runtime

WORKDIR /app

# Install OpenSSL, which is dynamically linked by some of our dependencies.
# Install ca-certificates, which is needed to verify TLS certificates when
# establishing HTTPS connections.
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    # Clean up
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Copy the compiled binary from the builder environment to our runtime
# environment.
COPY --from=builder /app/target/release/zero2prod zero2prod

# We need the configuration file at runtime.
COPY configuration configuration

ENV APP_ENVIRONMENT production

# When `docker run` is executed, launch the binary
ENTRYPOINT ["./zero2prod"]
