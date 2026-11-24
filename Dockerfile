FROM ghcr.io/berriai/litellm:v1.110.3@sha256:1050d2c9ca58399de9cd51df6eb503812af697717f54d2f08c1c30589c75e1f7

COPY ./scripts/load_secrets_and_run.sh /app/load_secrets_and_run.sh
COPY ./config.yaml /app/config.yaml
RUN chmod 755 /app/load_secrets_and_run.sh

EXPOSE 4000

ENTRYPOINT ["/app/load_secrets_and_run.sh"]

CMD ["docker/prod_entrypoint.sh", "--config", "/app/config.yaml", "--port", "4000", "--num_workers", "1"]
