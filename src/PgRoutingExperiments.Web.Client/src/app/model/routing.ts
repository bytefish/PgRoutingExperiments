/**
 * @summary Transportation Types
 */
export type TransportMode = 'car' | 'bike' | 'foot';


export interface TransportModeOption {
  id: TransportMode;
  label: string;
}
/**
 * @summary Routing Options
 */
export interface RouteOptions {
  avoid_motorway?: boolean;
  exclude_motorway?: boolean;
  avoid_ferry?: boolean;
  optimize_consumption?: boolean;
}
