
-- =========================================================================
-- Required Extensions
-- =========================================================================
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS hstore;

-- =========================================================================
-- Lookup Table for Cities
-- =========================================================================
-- 
-- Create a view to rank cities by importance/population
DROP TABLE IF EXISTS city_popularity;

CREATE TABLE city_popularity (
    city_name TEXT PRIMARY KEY,
    population INT,
    place_rank INT
);

-- Populations for approximately 150 municipalities in Regierungsbezirk Münster and nearby regions
INSERT INTO city_popularity (city_name, population, place_rank) VALUES
('Gelsenkirchen', 260126, 4), ('Münster', 317713, 4), ('Bottrop', 117388, 4),
('Recklinghausen', 110705, 4), ('Marl', 83697, 3), ('Rheine', 76000, 3),
('Gladbeck', 75520, 3), ('Dorsten', 74551, 3), ('Castrop-Rauxel', 73425, 3),
('Bocholt', 71000, 3), ('Lünen', 86000, 3), ('Menden', 53000, 3),
('Herten', 61910, 3), ('Ahlen', 52500, 3), ('Ibbenbüren', 51000, 3),
('Dülmen', 47000, 3), ('Gronau', 49000, 3), ('Schwerte', 46000, 3),
('Haltern am See', 38000, 3), ('Borken', 42000, 3), ('Beckum', 37000, 3),
('Emsdetten', 36000, 3), ('Ahaus', 39000, 3), ('Lüdinghausen', 25000, 2),
('Steinfurt', 34000, 3), ('Werne', 29000, 2), ('Oer-Erkenschwick', 31000, 2),
('Waltrop', 29000, 2), ('Datteln', 34000, 3), ('Greven', 37000, 3),
('Senden', 20000, 2), ('Telgte', 20000, 2), ('Vreden', 22000, 2),
('Stadtlohn', 20000, 2), ('Gescher', 17000, 2), ('Coesfeld', 36000, 3),
('Warendorf', 37000, 3), ('Lengerich', 22000, 2), ('Oelde', 29000, 2),
('Ennigerloh', 20000, 2), ('Ascheberg', 15000, 2), ('Billerbeck', 11500, 2),
('Havixbeck', 11800, 2), ('Sendenhorst', 13000, 2), ('Metelen', 6400, 1),
('Heek', 8600, 1), ('Legden', 7300, 1), ('Rosendahl', 10800, 2),
('Südlohn', 9000, 1), ('Heiden', 8200, 1), ('Raesfeld', 11500, 2),
('Reken', 14000, 2), ('Isselburg', 10700, 2), ('Olfen', 13000, 2),
('Nordkirchen', 10000, 2), ('Ostbevern', 11000, 2), ('Beelen', 6000, 1),
('Everswinkel', 9600, 1), ('Wadersloh', 12000, 2), ('Ladbergen', 6700, 1),
('Saerbeck', 7100, 1), ('Tecklenburg', 9000, 1), ('Westerkappeln', 11000, 2),
('Lotte', 14000, 2), ('Mettingen', 12000, 2), ('Recke', 11000, 2),
('Hopsten', 7600, 1), ('Hörstel', 20000, 2), ('Altenberge', 10000, 2),
('Laer', 6700, 1), ('Horstmar', 6600, 1), ('Ochtrup', 19000, 2),
('Wettringen', 8200, 1), ('Nordwalde', 9500, 1), ('Neuenkirchen', 13800, 2),
('Alverskirchen', 1500, 1), ('Gimbte', 1000, 1), ('Angelmodde', 8000, 1),
 ('Albachten', 6500, 1), ('Nienberge', 7000, 1),
('Roxel', 9000, 1), ('Wolbeck', 9500, 1), ('Handorf', 8000, 1),
('Hiltrup', 25000, 2), ('Kinderhaus', 15000, 2), ('Sprakel', 3000, 1),
('Gievenbeck', 20000, 2), ('Coerde', 10000, 1), ('Berg Fidel', 6000, 1),
('Mauritz', 15000, 2), ('Mecklenbeck', 9000, 1), ('Sentrup', 5000, 1),
('Überwasser', 10000, 1), ('Aaseestadt', 8000, 1), ('Rumphorst', 4000, 1),
('Albersloh', 3500, 1), ('Walstedde', 3000, 1), ('Vorhelm', 4500, 1), 
('Neubeckum', 10000, 1), ('Lette', 2200, 1),
('Buldern', 6000, 1), ('Hiddingsel', 1500, 1), ('Hausdülmen', 2000, 1),
('Merfeld', 2000, 1), ('Rorup', 2200, 1), ('Darup', 2000, 1),
('Holtwick', 3500, 1), ('Osterwick', 5000, 1), ('Beerlage', 1000, 1), 
('Schapdetten', 1200, 1), ('Capelle', 2000, 1),
('Südkirchen', 3500, 1), ('Oeding', 3800, 1), ('Alstätte', 5000, 1),
('Graes', 1200, 1), ('Ottenstein', 3800, 1), ('Wüllen', 5500, 1),
('Lünten', 1200, 1), ('Ellewick', 1000, 1), ('Ammeloe', 1500, 1),
('Hochmoor', 2500, 1), ('Tungerloh', 1000, 1), ('Estern', 800, 1),
('Büren', 1000, 1), ('Liesborn', 3500, 1), ('Diestedde', 2500, 1),
('Benteler', 2200, 1), ('Mastholte', 6500, 1), ('Stromberg', 4500, 1),
('Lette (Oelde)', 2200, 1), ('Sünninghausen', 1200, 1), ('Herbern', 5000, 1),
('Bösensell', 2800, 1), ('Appelhülsen', 4500, 1), ('Ottmarsbocholt', 3500, 1),
('Rinkerode', 3800, 1), ('Amelsbüren', 6000, 1), ('Seppenrade', 7000, 1),
('Hullern', 2500, 1), ('Lavesum', 1800, 1), ('Sythen', 6000, 1),
('Hamm-Bossendorf', 2000, 1), ('Flaesheim', 2500, 1), ('Lippramsdorf', 3500, 1),
('Lembeck', 5000, 1), ('Wulfen', 13000, 2), ('Rhade', 5500, 1),
('Holsterhausen', 15000, 2), ('Hervest', 13000, 2), ('Altendorf-Ulfkotte', 2000, 1),
('Feldhausen', 1500, 1), ('Kirchhellen', 20000, 2), ('Grafenwald', 6000, 1),
('Eigen', 15000, 2), ('Boy', 10000, 1), ('Welheim', 8000, 1),
('Buer', 30000, 3), ('Horst', 20000, 2), ('Schalke', 15000, 2),
('Erle', 15000, 2), ('Resse', 12000, 2), ('Hassel', 15000, 2),
('Westerholt', 10000, 1), ('Bertlich', 5000, 1), ('Polsum', 4500, 1),
('Langenbochum', 10000, 1), ('Disteln', 10000, 1), ('Scherlebeck', 10000, 1),
('Stuckenbusch', 5000, 1), ('Hochlar', 8000, 1), ('Quellberg', 8000, 1),
('Grönwohld', 1500, 1);

-- Create an index for the join
CREATE INDEX idx_popularity_city_name ON city_popularity (city_name);
-- =========================================================================
-- Geocode Search Index
-- =========================================================================
DROP TABLE IF EXISTS geocode_search_idx;

-- Create a unified search table combining points and polygons
CREATE TABLE geocode_search_idx AS
WITH base_data AS (
    SELECT 
        osm_id,
        tags->'addr:housenumber' as housenumber,
        tags->'addr:street' as street,
        tags->'addr:city' as city,
        tags->'addr:postcode' as plz,
        'Germany' as country,
        ST_Centroid(way) as geom
    FROM planet_osm_point 
    WHERE tags ? 'addr:street'
    UNION ALL
    SELECT 
        osm_id,
        tags->'addr:housenumber',
        tags->'addr:street',
        tags->'addr:city',
        tags->'addr:postcode',
        COALESCE(tags->'addr:country', 'Germany'),
        ST_Centroid(way)
    FROM planet_osm_polygon
    WHERE tags ? 'addr:street'
)
SELECT 
    b.*,
    COALESCE(p.population, 1000) as city_pop,
    COALESCE(p.place_rank, 1) as city_importance,
    -- Concatenate fields for trigram matching
    (COALESCE(b.street, '') || ' ' || COALESCE(b.housenumber, '') || ' ' || 
     COALESCE(b.plz, '') || ' ' || COALESCE(b.city, '') || ' Germany Deutschland') as full_address
FROM base_data b
-- Join via text name instead of geometry for better reliability
LEFT JOIN city_popularity p ON b.city = p.city_name;

-- Indexes for fast German-style searching and spatial proximity
CREATE INDEX idx_full_addr_trgm ON geocode_search_idx USING gin (full_address gin_trgm_ops);
CREATE INDEX idx_plz_exact ON geocode_search_idx (plz);
CREATE INDEX idx_search_geom_gist ON geocode_search_idx USING GIST (geom);
CREATE INDEX idx_street_trgm ON geocode_search_idx USING gin (street gin_trgm_ops);
CREATE INDEX idx_city_trgm ON geocode_search_idx USING gin (city gin_trgm_ops);


-- =========================================================================
-- Search Functions for Germany
-- =========================================================================
CREATE OR REPLACE FUNCTION geocode_german_address(
    search_text TEXT, 
    ref_lat FLOAT DEFAULT NULL, 
    ref_lon FLOAT DEFAULT NULL
)
RETURNS TABLE (
    street TEXT,
    housenumber TEXT,
    plz TEXT,
    city TEXT,
    country TEXT,
    lat FLOAT,
    lon FLOAT,
    score FLOAT
) AS $$
DECLARE
    input_plz TEXT;
    input_house TEXT;
    clean_search TEXT;
BEGIN
    -- 1. Pre-process search text
    clean_search := trim(search_text);
    input_plz := (substring(clean_search from '\y(\d{5})\y'));
    input_house := (substring(clean_search from '\y(?!\d{5})(\d+[a-zA-Z]?)\y'));

    RETURN QUERY
    SELECT 
        idx.street, 
        idx.housenumber, 
        idx.plz, 
        idx.city,
        idx.country,
        ST_Y(ST_Transform(idx.geom, 4326))::FLOAT as out_lat,
        ST_X(ST_Transform(idx.geom, 4326))::FLOAT as out_lon,
        (
            -- TEXT SIMILARITY (0.3)
            (similarity(idx.full_address, clean_search) * 0.3) +   
            
            -- STREET SIMILARITY (0.2)
            (similarity(idx.street, clean_search) * 0.2) +

            -- CITY NAME BOOST (0.15)
            (similarity(idx.city, clean_search) * 0.15) +

            -- WORD MATCH BONUS (0.1)
            (CASE 
                WHEN idx.street ILIKE clean_search THEN 0.1
                WHEN idx.street ILIKE clean_search || '%' THEN 0.05 
                ELSE 0 
            END) +
            
            -- POPULATION WEIGHT (0.25)
            -- Primary anchor for importance. 
            (LN(GREATEST(idx.city_pop, 1)) / 15.0 * 0.25) +       
            
            -- PROXIMITY WEIGHT (0.3)
            (CASE 
                WHEN ref_lat IS NOT NULL AND ref_lon IS NOT NULL THEN
                    (1.0 / (1.0 + ST_Distance(
                        ST_Transform(idx.geom, 4326)::geography, 
                        ST_SetSRID(ST_MakePoint(ref_lon, ref_lat), 4326)::geography
                    ) / 3000.0)) * 0.3 
                ELSE 0 
            END)
        )::FLOAT as final_score
    FROM geocode_search_idx idx
    WHERE 
		((idx.city is not null) AND
        ((input_plz IS NOT NULL AND idx.plz = input_plz AND (idx.street % clean_search OR idx.full_address % clean_search))
        OR
        (input_plz IS NULL AND (idx.street % clean_search OR idx.full_address % clean_search OR idx.city % clean_search))))
    ORDER BY final_score DESC
    LIMIT 15;
END;
$$ LANGUAGE plpgsql STABLE;

SELECT * FROM geocode_german_address('Breul');


