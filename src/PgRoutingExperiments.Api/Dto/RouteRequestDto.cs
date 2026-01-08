// Licensed under the MIT license. See LICENSE file in the project root for full license information.

namespace PgRoutingExperiments.Api.Dto;

public class RouteRequestDto
{
    public required string Mode { get; set; }

    public required double StartLon { get; set; }

    public required double StartLat { get; set; }

    public required double EndLon { get; set; }

    public required double EndLat { get; set; }

    public RouteOptionsDto Options { get; set; } = new RouteOptionsDto();
}
