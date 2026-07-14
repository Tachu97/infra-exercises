# ── Build stage: not needed (pre-built binary) ────────────────────────────────
# We use debian:bookworm-slim rather than scratch so the binary can resolve
# shared libc dependencies if needed, while still keeping the image small.
FROM debian:bookworm-slim

WORKDIR /app

# Copy the pre-built linux/amd64 binary
COPY app/rest_1.0_linux_amd64 ./rest

RUN chmod +x ./rest

# Run as a non-root user for security
RUN useradd --no-create-home --shell /bin/false appuser
USER appuser

EXPOSE 8080

ENTRYPOINT ["./rest"]
