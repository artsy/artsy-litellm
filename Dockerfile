FROM ghcr.io/berriai/litellm:v1.104.2@sha256:3d88bd757134a00e8c00237b85a021ab1f6d54abb9c1df750f411dbe7256a500

COPY ./scripts/load_secrets_and_run.sh /app/load_secrets_and_run.sh
COPY ./config.yaml /app/config.yaml
RUN chmod 755 /app/load_secrets_and_run.sh

EXPOSE 4000

ENTRYPOINT ["/app/load_secrets_and_run.sh"]

CMD ["docker/prod_entrypoint.sh", "--config", "/app/config.yaml", "--port", "4000", "--num_workers", "1"]
