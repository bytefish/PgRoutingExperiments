// Licensed under the MIT license. See LICENSE file in the project root for full license information.

using System.Text.Json.Serialization;

namespace PgRoutingExperiments.Api.Dto;

public class RouteOptionsDto
{
    [JsonPropertyName("avoid_motorway")]
    public bool AvoidMotorway { get; set; } = false;

    [JsonPropertyName("exclude_motorway")]
    public bool ExcludeMotorway { get; set; } = false;

    [JsonPropertyName("avoid_ferry")]
    public bool AvoidFerry { get; set; } = false;

    [JsonPropertyName("optimize_consumption")]
    public bool OptimizeConsumption { get; set; } = false;
}
