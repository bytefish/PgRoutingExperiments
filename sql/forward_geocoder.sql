-- =========================================================================
-- Lookup Table for Weights
-- =========================================================================
-- 
-- weighting our query by ranking the population.
CREATE MATERIALIZED VIEW city_popularity AS
SELECT 
    name,
    way as geom,
    CASE 
        WHEN population ~ '^[0-9]+$' THEN population::numeric 
        WHEN place = 'city' THEN 100000
        WHEN place = 'town' THEN 10000
        ELSE 1000 
    END as est_pop,
    CASE 
        WHEN place = 'city' THEN 4
        WHEN place = 'town' THEN 3
        WHEN place = 'village' THEN 2
        ELSE 1
    END as place_rank
FROM planet_osm_polygon
WHERE place IN ('city', 'town', 'village', 'hamlet')
   OR (boundary = 'administrative' AND admin_level = '8');

CREATE INDEX idx_city_pop_geom ON city_popularity USING GIST (geom);

-- =========================================================================
-- Geocode Search Index
-- =========================================================================
DROP TABLE IF EXISTS geocode_search_idx;

CREATE TABLE geocode_search_idx AS
WITH base_data AS (
    SELECT 
        osm_id,
        "addr:housenumber" as housenumber,
        "addr:street" as street,
        "addr:city" as city,
        "addr:postcode" as plz,
        ST_Centroid(way) as geom
    FROM planet_osm_point 
    WHERE "addr:street" IS NOT NULL
    UNION ALL
    SELECT 
        osm_id,
        "addr:housenumber",
        "addr:street",
        "addr:city",
        "addr:postcode",
        ST_Centroid(way)
    FROM planet_osm_polygon
    WHERE "addr:street" IS NOT NULL
)
SELECT 
    b.*,
    COALESCE(p.est_pop, 0) as city_pop,
    COALESCE(p.place_rank, 0) as city_importance,
    (COALESCE(b.street, '') || ' ' || COALESCE(b.housenumber, '') || ' ' || COALESCE(b.plz, '') || ' ' || COALESCE(b.city, '')) as full_address
FROM base_data b
LEFT JOIN city_popularity p ON ST_Intersects(b.geom, p.geom);

-- Indexes for fast German-style searching
CREATE INDEX idx_full_addr_trgm ON geocode_search_idx USING gin (full_address gin_trgm_ops);
CREATE INDEX idx_plz_exact ON geocode_search_idx (plz);

-- =========================================================================
-- Search Functions for Germany
-- =========================================================================
CREATE OR REPLACE FUNCTION geocode_german_address(search_text TEXT)
RETURNS TABLE (
    street TEXT,
    housenumber TEXT,
    plz TEXT,
    city TEXT,
    lat FLOAT,
    lon FLOAT,
    score FLOAT
) AS $$
DECLARE
    input_plz TEXT;
    input_house TEXT;
BEGIN
    -- 1. Extract exactly 5 digits for German PLZ
    input_plz := (substring(search_text from '\y(\d{5})\y'));
    
    -- 2. Extract House Number (digits not part of a 5-digit sequence)
    input_house := (substring(search_text from '\y(?!\d{5})(\d+[a-zA-Z]?)\y'));

    RETURN QUERY
    SELECT 
        idx.street, 
        idx.housenumber, 
        idx.plz, 
        idx.city,
        ST_Y(ST_Transform(idx.geom, 4326))::FLOAT as lat,
        ST_X(ST_Transform(idx.geom, 4326))::FLOAT as lon,
        (
            (similarity(idx.full_address, search_text) * 0.4) +
            (CASE WHEN idx.plz = input_plz THEN 0.3 ELSE 0 END) +
            (CASE WHEN idx.housenumber = input_house THEN 0.2 ELSE 0 END) +
            (LN(GREATEST(idx.city_pop, 1)) / 20.0 * 0.1)
        )::FLOAT as final_score
    FROM geocode_search_idx idx
    WHERE 
        -- Optimization: If PLZ is found, filter by it first
        (input_plz IS NOT NULL AND idx.plz = input_plz AND (idx.street % search_text OR idx.full_address % search_text))
        OR
        -- Global fuzzy search
        (input_plz IS NULL AND idx.full_address % search_text)
    ORDER BY final_score DESC
    LIMIT 10;
END;
$$ LANGUAGE plpgsql STABLE;