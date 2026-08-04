/**
 * NestJS Map Matching API contract (P1).
 * Implement these DTOs/endpoints in the Trip Track Nest API.
 *
 * REST (under global prefix, e.g. /api):
 *   GET  /travel-requests/:id/matched-route
 *   POST /travel-requests/:id/match   body: { reason: MatchReason }
 *
 * Socket.IO namespace `/tracking`:
 *   emit to trip room → `route.matched` (same payload as MatchedRouteResultDto)
 *
 * Matching engine (MVP): Google Roads Snap-to-Roads (batch, ≤100 pts/req).
 * Do NOT snap on every GPS tick. Rematch on: catch_up | incremental | trip_end.
 */

export type MatchReason = 'catch_up' | 'trip_end' | 'incremental' | 'manual';

export type RouteSegmentKind =
  | 'gps_verified'
  | 'map_matched'
  | 'estimated';

export type MatchJobStatus = 'pending' | 'ready' | 'failed';

export interface TriggerMatchDto {
  reason: MatchReason;
}

export interface RouteSegmentDto {
  segId: string;
  legId?: string;
  kind: RouteSegmentKind;
  /** 0–1 */
  confidence: number;
  lengthM: number;
  fromTimestamp?: string;
  toTimestamp?: string;
  /** Pipe polyline: "lat,lng|lat,lng|..." */
  polylineEncoded: string;
  matchMethod?: 'google_roads' | 'valhalla_meili' | 'osrm' | string;
}

export interface MatchedLegMetricsDto {
  legId: string;
  officialDistanceKm?: number;
  provisionalDistanceKm?: number;
  confidence?: number;
  estimatedPct?: number;
  matchedPolylineEncoded?: string;
  segments: RouteSegmentDto[];
}

export interface MatchedRouteResultDto {
  requestId: string;
  status: MatchJobStatus;
  engine?: string;
  matchedAt?: string;
  officialDistanceKm?: number;
  provisionalDistanceKm?: number;
  coveragePct?: number;
  matchedPct?: number;
  estimatedPct?: number;
  legs: MatchedLegMetricsDto[];
  segments: RouteSegmentDto[];
  error?: string;
}

/**
 * Suggested Nest worker flow:
 * 1. Ingest route-points/batch (idempotent upsert by pointId).
 * 2. Enqueue MatchJob { requestId, fromSeq, toSeq, reason }.
 * 3. Downsample trail (~1 pt / 15–25m), chunk ≤100, Snap-to-Roads interpolate=true.
 * 4. Build RouteSegmentDto[] with kinds + confidence; sum edge lengths → officialDistanceKm.
 * 5. Persist route_segments + leg_metrics; PATCH travel-request totals.
 * 6. WS emit `route.matched` to user + admin rooms for requestId.
 */
export interface MatchJobDocument {
  jobId: string;
  requestId: string;
  status: MatchJobStatus;
  reason: MatchReason;
  fromSeq?: number;
  toSeq?: number;
  engine: string;
  error?: string;
  createdAt: string;
  finishedAt?: string;
}
