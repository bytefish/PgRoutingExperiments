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
    public class GeocodeController : ControllerBase
    {
        private readonly ILogger<MbTilesController> _logger;

        private readonly ApplicationOptions _applicationOptions;

        public GeocodeController(ILogger<MbTilesController> logger, IOptions<ApplicationOptions> applicationOptions)
        {
            _logger = logger;
            _applicationOptions = applicationOptions.Value;
        }

        [HttpGet]
        [Route("/geocode")]
        public async Task<ActionResult> Get([FromQuery] string query, [FromQuery] double? refLat, [FromQuery] double? refLon)
        {
            using var connection = new NpgsqlConnection(_applicationOptions.ConnectionString);

            const string sql = @"
                SELECT street, housenumber, plz, city, country, lat, lon, score 
                FROM geocode_german_address(@query, @refLat, @refLon)";

            try
            {
                var results = await connection.QueryAsync(sql, new { query, refLat, refLon });

                return Ok(results);
            }
            catch (Exception ex)
            {
                return Problem($"Geocode failed: {ex.Message}");
            }
        }
    }
}