// Versioned model URLs. /models lets browsers cache files for a day, so an
// updated model would only show up in a fresh browser. The LiveView sends a short
// version per file (BaconWorld.Models.asset_versions/0, from size and mtime), and
// every model, texture and thumbnail URL gets it as ?vsn=..., so a changed file is a
// new URL and an unchanged one stays cached.
let versions: Record<string, string> = {};

export function setAssetVersions(map: unknown): void {
  versions = map && typeof map === 'object' ? (map as Record<string, string>) : {};
}

/** `url` with its version added when it is a /models file the server knows. */
export function modelUrl(url: string): string {
  const m = /^\/models\/([^?#]+)$/.exec(url);
  if (!m) return url;
  let rel = m[1];
  try {
    rel = decodeURIComponent(rel);
  } catch {
    // keep it as it is
  }
  const v = versions[rel];
  return v ? `${url}?vsn=${encodeURIComponent(v)}` : url;
}
// (Plug.Static treats a `vsn` query as a versioned request and lets browsers keep
// the file for a year, `immutable`, instead of revalidating it daily.)
