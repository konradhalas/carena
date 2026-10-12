# Dedicated game server image. Expects the server export in build/server:
#   godot --headless --export-release "Linux Server" build/server/carena-server.x86_64
#   docker build --platform linux/amd64 -t carena-server .
#   docker run -p 7777:7777/udp carena-server [--match-time=300 --kill-limit=20]
FROM debian:bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/konradhalas/carena"
LABEL org.opencontainers.image.description="Carena dedicated game server"

RUN useradd --create-home --uid 1000 carena
COPY --chown=carena:carena build/server/carena-server.x86_64 /app/carena-server
USER carena
WORKDIR /home/carena

EXPOSE 7777/udp
ENTRYPOINT ["/app/carena-server", "--headless", "--", "--server"]
