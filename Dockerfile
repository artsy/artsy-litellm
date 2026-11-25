FROM ghcr.io/berriai/litellm:v1.111.0@sha256:ce00096d012719d58c52cecfa373f7c6256dd1b0ff08f6fa607e10e9628f1f46

COPY ./scripts/load_secrets_and_run.sh /app/load_secrets_and_run.sh
COPY ./config.yaml /app/config.yaml

EXPOSE 4000

ENTRYPOINT ["/app/load_secrets_and_run.sh"]

CMD ["/app/docker-entrypoint.sh", "proxy", "--config", "/app/config.yaml", "--port", "4000", "--num_workers", "1"]
