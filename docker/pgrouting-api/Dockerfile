FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /source

COPY ../src/PgRoutingExperiments.Api/*.csproj ./PgRoutingExperiments.Api/

RUN dotnet restore "PgRoutingExperiments.Api/PgRoutingExperiments.Api.csproj"

COPY ../src/PgRoutingExperiments.Api/. ./src/PgRoutingExperiments.Api/

RUN dotnet publish ./src/PgRoutingExperiments.Api/PgRoutingExperiments.Api.csproj -c release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0

WORKDIR /app
COPY --from=build /app ./

ENTRYPOINT ["dotnet", "PgRoutingExperiments.Api.dll"]