FROM ghcr.io/berriai/litellm:v1.106.2@sha256:7294b90f868c5c38c99b83021c7ba46f9b439e95f8e32964c925c7d2563a03f7

COPY ./scripts/load_secrets_and_run.sh /app/load_secrets_and_run.sh
COPY ./config.yaml /app/config.yaml
RUN chmod 755 /app/load_secrets_and_run.sh

EXPOSE 4000

ENTRYPOINT ["/app/load_secrets_and_run.sh"]

CMD ["docker/prod_entrypoint.sh", "--config", "/app/config.yaml", "--port", "4000", "--num_workers", "1"]
