-- =============================================================
-- PREPARATION
-- =============================================================
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgrouting;
CREATE EXTENSION IF NOT EXISTS hstore;

-- =============================================================
-- SCHEMA
-- =============================================================
CREATE SCHEMA IF NOT EXISTS routing;
