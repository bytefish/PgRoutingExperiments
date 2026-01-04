// Licensed under the MIT license. See LICENSE file in the project root for full license information.

using Dapper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Npgsql;
using PgRoutingExperiments.Api.Options;
using System.Text.Json;

namespace PgRoutingExperiments.Api.Controllers
{
    [ApiController]
    public class RoutingController : ControllerBase
    {
        private readonly ILogger<MbTilesController> _logger;

        private readonly ApplicationOptions _applicationOptions;

        public RoutingController(ILogger<MbTilesController> logger, IOptions<ApplicationOptions> applicationOptions)
        {
            _logger = logger;
            _applicationOptions = applicationOptions.Value;
        }

        [HttpGet]
        [Route("/route")]
        public async Task<ActionResult> Get([FromQuery] string mode,
            [FromQuery] double startLon, [FromQuery] double startLat,
            [FromQuery] double endLon, [FromQuery] double endLat,
            [FromQuery] double? bbox_buffer = null)
        {
            if (bbox_buffer == null)
            {
                bbox_buffer = EstimateDynamicBuffer(mode, startLon, startLat, endLon, endLat);
            }

            using var connection = new NpgsqlConnection(_applicationOptions.ConnectionString);

            // 2. Query the database using our optimized function
            const string sql = @"
                    SELECT 
                        out_seq     AS ""seq"", 
                        out_name    AS ""name"", 
                        out_type    AS ""type"", 
                        out_seconds AS ""seconds"", 
                        ST_AsGeoJSON(out_geom)::json as geometry 
                    FROM get_route(@mode, @startLon, @startLat, @endLon, @endLat, @bbox_buffer)";

            try
            {
                IEnumerable<dynamic> rows = await connection.QueryAsync(sql, new 
                { 
                    mode, 
                    startLon, 
                    startLat, 
                    endLon, 
                    endLat,
                    bbox_buffer
                });

                dynamic features = rows.Select(row => new
                {
                    type = "Feature",
                    geometry = JsonDocument.Parse(row.geometry).RootElement,
                    properties = new
                    {
                        row.seq,
                        row.name,
                        row.type,
                        row.seconds,
                        appliedBuffer = bbox_buffer
                    }
                });

                var bboxJson = new
                {
                    minLon = Math.Min(startLon, endLon) - bbox_buffer,
                    minLat = Math.Min(startLat, endLat) - bbox_buffer,
                    maxLon = Math.Max(startLon, endLon) + bbox_buffer,
                    maxLat = Math.Max(startLat, endLat) + bbox_buffer
                };

                return Ok(new
                {
                    type = "FeatureCollection",
                    features = features,
                    debugBBox = bboxJson
                });
            }
            catch (Exception ex)
            {
                return Problem($"Routing failed: {ex.Message}");
            }
        }

        private static double EstimateDynamicBuffer(string mode, double startLon, double startLat, double endLon, double endLat)
        {
            // Calculate the distance between start and end points (Euclidean distance)
            double deltaLon = Math.Abs(startLon - endLon);
            double deltaLat = Math.Abs(startLat - endLat);
            double distance = Math.Sqrt(deltaLon * deltaLon + deltaLat * deltaLat);

            // Dynamic Buffer Calculation based on mode and distance
            double bufferFactor = mode switch
            {
                "car" => 0.20,  // 20%
                "bike" => 0.10, // 10%
                "walk" => 0.05, // 5%
                _ => 0.10 // default 10%
            };

            double calculatedBuffer = distance * bufferFactor;

            // Constrain the buffer to reasonable limits (0.005 = ca. 550m, 0.5 = ca. 55km)
            double finalBuffer = Math.Clamp(calculatedBuffer, 0.005, 0.5);

            return finalBuffer;
        }
    }
}