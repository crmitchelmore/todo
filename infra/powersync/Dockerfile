# PowerSync service for Railway (and any image-based deploy).
# Bakes the service + sync-rules config into the image so no volume mount is needed.
# Connection URIs (source + bucket storage) and JWKS URL are injected via env vars.
FROM journeyapps/powersync-service:latest

COPY service.yaml sync-config.yaml /config/
ENV POWERSYNC_CONFIG_PATH=/config/service.yaml

# Inherit the base image ENTRYPOINT; run the unified service.
CMD ["start", "-r", "unified"]
