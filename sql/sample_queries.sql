-- Sample Queries for Start and Endpoints.
--
-- [Hafenweg 46, Münster (7.64966, 51.95111)] -> [Breul 43, Münster: (7.62399, 51.96620)]
-- 
SELECT * FROM get_route('car', 7.64966, 51.95111, 7.62399, 51.96620);
SELECT * FROM get_route('bike', 7.64966, 51.95111, 7.62399, 51.96620);
SELECT * FROM get_route('walk', 7.64966, 51.95111, 7.62399, 51.96620);
