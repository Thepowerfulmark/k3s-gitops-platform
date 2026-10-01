FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --uid 65532 --create-home --shell /usr/sbin/nologin app
COPY --chown=65532:65532 app ./app
USER 65532
EXPOSE 8080
ENTRYPOINT ["python", "-m", "app"]
CMD ["serve"]
