# Map Matching Contract (P1)

Flutter client is wired for:

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/travel-requests/:id/matched-route` | Latest official route + km |
| `POST` | `/travel-requests/:id/match` | Enqueue rematch (`reason`) |

| Socket event | Namespace | Payload |
|--------------|-----------|---------|
| `route.matched` | `/tracking` | `MatchedRouteResultDto` |

See `matched-route.contract.ts` for DTOs.

## Worker rules

1. Never Snap-to-Roads on every GPS tick.
2. Rematch on `catch_up` (after batch upload), `incremental` (leg arrival), `trip_end`.
3. Official km = sum of matched road geometry lengths, not Haversine of raw GPS.
4. Segment kinds: `gps_verified` | `map_matched` | `estimated`.
5. Do not force drivers onto the planned Directions polyline.

## Mongo collections (suggested)

- `route_segments`
- `leg_metrics` (or fields on trip legs)
- `match_jobs`
