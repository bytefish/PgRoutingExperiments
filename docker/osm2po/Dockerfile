FROM eclipse-temurin:21-jre-jammy

WORKDIR /app

RUN apt-get update && apt-get install -y wget unzip && \
    wget https://osm2po.de/releases/osm2po-5.5.5.zip && \
    unzip osm2po-5.5.5.zip && \
    rm osm2po-5.5.5.zip

CMD ["java", "-Xmx2g", "-jar", "osm2po-core.jar"]