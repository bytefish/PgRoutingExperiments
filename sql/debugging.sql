-- =========================================================================
-- DEBUG DATA (OSM2PO VERSION)
-- =========================================================================
CREATE SCHEMA IF NOT EXISTS debugging;

DROP TABLE IF EXISTS debugging.network_islands;

CREATE TABLE debugging.network_islands AS
WITH component_analysis AS (
    SELECT * FROM pgr_connectedComponents(
        'SELECT id, source, target, cost AS cost FROM routing.osm2po_data'
    )
)
SELECT 
    osm.id, 
    osm.geom_way AS geom, 
    osm.source, 
    osm.target, 
    ca.component AS component_id
FROM routing.osm2po_data osm
JOIN component_analysis ca ON osm.source = ca.node; 

-- Indices for faster lookups
CREATE INDEX idx_islands_comp ON debugging.network_islands(component_id);
CREATE INDEX idx_network_islands_geom ON debugging.network_islands USING GIST (geom);