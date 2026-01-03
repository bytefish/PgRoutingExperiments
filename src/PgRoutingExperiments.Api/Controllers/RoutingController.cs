// Licensed under the MIT license. See LICENSE file in the project root for full license information.

using Dapper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Npgsql;
using PgRoutingExperiments.Api.Options;

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
            [FromQuery] double endLon, [FromQuery] double endLat)
        {
            using var connection = new NpgsqlConnection(_applicationOptions.ConnectionString);

            // 2. Query the database using our optimized function
            const string sql = @"
                    SELECT 
                        seq, 
                        display_name as name, 
                        road_type as type, 
                        seconds, 
                        ST_AsGeoJSON(geom)::json as geometry 
                    FROM get_route(@mode, @startLon, @startLat, @endLon, @endLat)";

            try
            {
                IEnumerable<dynamic> rows = await connection.QueryAsync(sql, new { mode, startLon, startLat, endLon, endLat });

                dynamic features = rows.Select(row => new
                {
                    type = "Feature",
                    geometry = row.geometry,
                    properties = new
                    {
                        row.seq,
                        row.name,
                        row.type,
                        row.seconds
                    }
                });

                return Ok(new
                {
                    type = "FeatureCollection",
                    features = features
                });
            }
            catch (Exception ex)
            {
                return Problem($"Routing failed: {ex.Message}");
            }
        }
    }
}