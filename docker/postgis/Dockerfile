FROM postgis/postgis:17-3.5

RUN apt -y update \
    && apt -y install postgresql-17-pgrouting \
    && apt-get install -y osm2pgsql \
    && apt -y clean