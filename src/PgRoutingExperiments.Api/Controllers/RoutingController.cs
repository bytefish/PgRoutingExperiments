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
            [FromQuery] double endLon, [FromQuery] double endLat)
        {
            string transportMode = mode.ToLower() switch
            {
                "walk" => "foot",
                "bike" => "bike",
                _ => "car"
            };

            using var connection = new NpgsqlConnection(_applicationOptions.ConnectionString);

            const string sql = @"
                SELECT 
                    seq, 
                    osm_name as name, 
                    cost_time as seconds,
                    ST_AsGeoJSON(geom) as geometry 
                FROM routing.get_route(@startLon, @startLat, @endLon, @endLat, @transportMode)";

            try
            {
                var rows = await connection.QueryAsync<dynamic>(sql, new
                {
                    startLon,
                    startLat,
                    endLon,
                    endLat,
                    transportMode
                });

                if (!rows.Any())
                {
                    return NotFound(new { message = "No route found" });
                }

                var features = rows.Select(row => new {
                    type = "Feature",
                    geometry = JsonDocument.Parse((string)row.geometry).RootElement,
                    properties = new
                    {
                        seq = (int)row.seq,
                        name = (string)row.name,
                        seconds = (double)row.seconds * 3600
                    }
                });

                return Ok(new
                {
                    type = "FeatureCollection",
                    metadata = new { mode = transportMode },
                    features
                });
            }
            catch (Exception ex)
            {
                return Problem(ex.Message);
            }
        }
    }
}