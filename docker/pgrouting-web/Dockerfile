FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
RUN apt-get install nodejs -y

WORKDIR /data
COPY ../data/fonts/fonts.tar.xz ./fonts.tar.xz
 
WORKDIR /source

COPY ../src/PgRoutingExperiments.Web.Client/ ./PgRoutingExperiments.Web.Client/
COPY ../src/PgRoutingExperiments.Web.Server/ ./PgRoutingExperiments.Web.Server/

RUN dotnet restore "PgRoutingExperiments.Web.Server/PgRoutingExperiments.Web.Server.csproj"

WORKDIR /source/PgRoutingExperiments.Web.Client
RUN npm install

WORKDIR /source/PgRoutingExperiments.Web.Server

RUN dotnet publish -c release -o /app  /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0

WORKDIR /app

ADD ../data/fonts/fonts.tar.xz ./wwwroot/assets/fonts

COPY --from=build /app ./

ENTRYPOINT ["dotnet", "PgRoutingExperiments.Web.Server.dll"]