/**
 * Copy into NestJS as a starting point (Bull/BullMQ worker).
 * This file is a contract stub — not compiled by the Flutter app.
 */

import type {
  MatchJobDocument,
  MatchReason,
  MatchedRouteResultDto,
} from './matched-route.contract';

export interface MapMatchingWorkerDeps {
  loadRoutePoints(requestId: string): Promise<
    Array<{
      pointId: string;
      lat: number;
      lng: number;
      timestamp: string;
      accuracy?: number;
      legId?: string;
      seq?: number;
    }>
  >;
  snapToRoads(
    path: Array<{ lat: number; lng: number }>,
  ): Promise<Array<{ lat: number; lng: number; placeId?: string }>>;
  saveMatchedRoute(result: MatchedRouteResultDto): Promise<void>;
  emitRouteMatched(result: MatchedRouteResultDto): Promise<void>;
  createJob(job: MatchJobDocument): Promise<void>;
  finishJob(jobId: string, status: 'ready' | 'failed', error?: string): Promise<void>;
}

/** Downsample to ~1 point per 20m before Snap-to-Roads (max 100/chunk). */
export function downsampleForSnap(
  points: Array<{ lat: number; lng: number }>,
  minSpacingM = 20,
): Array<{ lat: number; lng: number }> {
  if (points.length <= 2) return points;
  const out = [points[0]];
  let last = points[0];
  for (let i = 1; i < points.length; i++) {
    const p = points[i];
    if (haversineM(last.lat, last.lng, p.lat, p.lng) >= minSpacingM) {
      out.push(p);
      last = p;
    }
  }
  if (out[out.length - 1] !== points[points.length - 1]) {
    out.push(points[points.length - 1]);
  }
  return out;
}

export function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

export async function enqueueMatch(
  deps: MapMatchingWorkerDeps,
  requestId: string,
  reason: MatchReason,
): Promise<MatchJobDocument> {
  const job: MatchJobDocument = {
    jobId: `match_${requestId}_${Date.now()}`,
    requestId,
    status: 'pending',
    reason,
    engine: 'google_roads',
    createdAt: new Date().toISOString(),
  };
  await deps.createJob(job);
  return job;
}

export async function runMatchJob(
  deps: MapMatchingWorkerDeps,
  job: MatchJobDocument,
): Promise<MatchedRouteResultDto> {
  try {
    const raw = await deps.loadRoutePoints(job.requestId);
    const down = downsampleForSnap(raw.map((p) => ({ lat: p.lat, lng: p.lng })));
    const snapped: Array<{ lat: number; lng: number }> = [];
    for (const part of chunk(down, 100)) {
      snapped.push(...(await deps.snapToRoads(part)));
    }

    const lengthM = pathLengthM(snapped);
    const polylineEncoded = snapped.map((p) => `${p.lat},${p.lng}`).join('|');
    const result: MatchedRouteResultDto = {
      requestId: job.requestId,
      status: 'ready',
      engine: job.engine,
      matchedAt: new Date().toISOString(),
      officialDistanceKm: Math.round((lengthM / 1000) * 1000) / 1000,
      legs: [],
      segments: [
        {
          segId: `${job.requestId}_full`,
          kind: 'map_matched',
          confidence: 0.75,
          lengthM,
          polylineEncoded,
          matchMethod: 'google_roads',
        },
      ],
    };

    await deps.saveMatchedRoute(result);
    await deps.emitRouteMatched(result);
    await deps.finishJob(job.jobId, 'ready');
    return result;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await deps.finishJob(job.jobId, 'failed', msg);
    return {
      requestId: job.requestId,
      status: 'failed',
      error: msg,
      legs: [],
      segments: [],
    };
  }
}

function haversineM(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

function pathLengthM(points: Array<{ lat: number; lng: number }>): number {
  let sum = 0;
  for (let i = 1; i < points.length; i++) {
    sum += haversineM(points[i - 1].lat, points[i - 1].lng, points[i].lat, points[i].lng);
  }
  return sum;
}
