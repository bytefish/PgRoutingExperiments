// Licensed under the MIT license. See LICENSE file in the project root for full license information.

using Dapper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Npgsql;
using PgRoutingExperiments.Api.Options;

namespace PgRoutingExperiments.Api.Controllers
{
    [ApiController]
    public class DebuggingController : ControllerBase
    {
        private readonly ILogger<MbTilesController> _logger;

        private readonly ApplicationOptions _applicationOptions;

        public DebuggingController(ILogger<MbTilesController> logger, IOptions<ApplicationOptions> applicationOptions)
        {
            _logger = logger;
            _applicationOptions = applicationOptions.Value;
        }

        [HttpGet("/debug/islands")]
        public async Task<IActionResult> GetIslands(
            [FromQuery] double minLon, [FromQuery] double minLat,
            [FromQuery] double maxLon, [FromQuery] double maxLat)
        {
            using var connection = new NpgsqlConnection(_applicationOptions.ConnectionString);

            const string sql = @"
                SELECT id, ST_AsGeoJSON(ST_Transform(geom, 4326)) as geometry, component_id 
                FROM debugging.network_islands
                AND geom && ST_MakeEnvelope(@minLon, @minLat, @maxLon, @maxLat, 4326)
                LIMIT 2000";

            var results = await connection.QueryAsync<dynamic>(sql, new { minLon, minLat, maxLon, maxLat });

            return Ok(results);
        }
    }
}