// Licensed under the MIT license. See LICENSE file in the project root for full license information.

namespace PgRoutingExperiments.Api.Options
{
    public class ApplicationOptions
    {
        /// <summary>
        /// Gets or sets the Tilesets available.
        /// </summary>
        public Dictionary<string, Tileset> Tilesets { get; set; } = new();
    }
}
