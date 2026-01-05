FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    osm2pgrouting \
    osmosis \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /data