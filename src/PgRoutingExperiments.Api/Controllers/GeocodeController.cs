// Licensed under the MIT license. See LICENSE file in the project root for full license information.

using Dapper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Npgsql;
using PgRoutingExperiments.Api.Options;

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
        public async Task<ActionResult> Geocode([FromQuery] string query, [FromQuery] double? refLat, [FromQuery] double? refLon)
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

        [HttpGet]
        [Route("/reverse-geocode")]
        public async Task<ActionResult> ReverseGeocode([FromQuery] double lat, [FromQuery] double lon)
        {
            using var connection = new NpgsqlConnection(_applicationOptions.ConnectionString);

            const string sql = @"
                SELECT street, housenumber, plz, city, country, distance_meters 
                FROM reverse_geocode_german_address(@lat, @lon)";

            try
            {
                var result = await connection.QueryFirstOrDefaultAsync<dynamic>(sql, new { lat, lon });

                return Ok(result);
            }
            catch (Exception ex)
            {
                return Problem($"Reverse Geocode failed: {ex.Message}");
            }
        }
    }
}