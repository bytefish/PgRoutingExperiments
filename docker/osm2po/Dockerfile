FROM eclipse-temurin:21-jre-jammy
WORKDIR /app

RUN mkdir -p /opt/osm2po

RUN apt-get update \
    && apt-get install -y wget unzip postgresql-client \
    && wget https://osm2po.de/releases/osm2po-5.5.5.zip \
    && unzip osm2po-5.5.5.zip -d /opt/osm2po