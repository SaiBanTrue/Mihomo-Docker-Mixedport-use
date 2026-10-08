FROM docker.io/library/alpine:latest

RUN apk add --no-cache bash curl tzdata yq

ENV TZ=Asia/Shanghai

WORKDIR /app

COPY ./app /app

VOLUME [ "/config" ]

ENTRYPOINT ["bash", "/app/entrypoint.sh"]
