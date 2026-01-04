-- =========================================================================
-- DEBUG DATA (OSM2PO VERSION)
-- =========================================================================
DROP TABLE IF EXISTS public.network_islands;

CREATE TABLE public.network_islands AS
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

-- Indizes für schnelle Abfragen im Frontend/Backend
CREATE INDEX idx_islands_comp ON public.network_islands(component_id);
CREATE INDEX idx_network_islands_geom ON public.network_islands USING GIST (geom);