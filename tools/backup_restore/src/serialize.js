"use strict";

// Firestore field values include types JSON has no native representation
// for (Timestamp, GeoPoint, DocumentReference, raw bytes). Round-tripping
// through JSON.stringify/parse without this codec silently turns a
// Timestamp into "{seconds, nanoseconds}" plain object -- which then fails
// firestore.rules's `is timestamp` checks on restore, and fails equality
// against the original on verification. Every such value is tagged with
// `__t` so fromPortable can rebuild the exact original type.
//
// The same problem exists for a handful of JS number values JSON simply
// cannot represent: JSON.stringify(NaN) / (Infinity) / (-Infinity) all
// produce the literal `null`, and JSON.stringify(-0) produces "0" -- so
// without special-casing them here, a document field holding one of these
// (a legal Firestore double) would silently and undetectably become `null`
// or `0` on restore. Ordinary finite numbers, including plain +0, are never
// tagged -- only these four exact values are.

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isUntaggableNumber(value) {
  return typeof value === "number" && (!Number.isFinite(value) || Object.is(value, -0));
}

function tagNumber(value) {
  if (Number.isNaN(value)) return "NaN";
  if (Object.is(value, -0)) return "-0";
  return value > 0 ? "Infinity" : "-Infinity";
}

function untagNumber(tag) {
  if (tag === "NaN") return NaN;
  if (tag === "-0") return -0;
  if (tag === "Infinity") return Infinity;
  if (tag === "-Infinity") return -Infinity;
  throw new Error(`serialize: unrecognised tagged number value ${JSON.stringify(tag)}`);
}

/**
 * Firestore document data -> plain JSON-safe value.
 *
 * Map keys are sorted so that exporting the same Firestore state twice
 * produces byte-identical JSON -- required for the archive to be a
 * deterministic artifact, not just a correct one.
 */
function toPortable(value, types) {
  const { Timestamp, GeoPoint, DocumentReference } = types;

  if (value === null || value === undefined) return null;
  if (isUntaggableNumber(value)) {
    return { __t: "number", v: tagNumber(value) };
  }
  if (value instanceof Timestamp) {
    return { __t: "timestamp", seconds: value.seconds, nanoseconds: value.nanoseconds };
  }
  if (value instanceof GeoPoint) {
    return { __t: "geopoint", latitude: value.latitude, longitude: value.longitude };
  }
  if (value instanceof DocumentReference) {
    return { __t: "reference", path: value.path };
  }
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    return { __t: "bytes", base64: Buffer.from(value).toString("base64") };
  }
  if (Array.isArray(value)) {
    return value.map((v) => toPortable(v, types));
  }
  if (isPlainObject(value)) {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      out[key] = toPortable(value[key], types);
    }
    return out;
  }
  // string, number, boolean
  return value;
}

/**
 * Plain JSON value (as produced by toPortable) -> Firestore document data,
 * for the TARGET project's Firestore instance. A `reference` is rebuilt
 * against `db` (the restore target), not the source project -- a restored
 * reference must point within the database it now lives in.
 */
function fromPortable(value, types, db) {
  const { Timestamp, GeoPoint } = types;

  if (value === null || value === undefined) return null;
  if (Array.isArray(value)) {
    return value.map((v) => fromPortable(v, types, db));
  }
  if (isPlainObject(value)) {
    if (value.__t === "number") {
      return untagNumber(value.v);
    }
    if (value.__t === "timestamp") {
      return new Timestamp(value.seconds, value.nanoseconds);
    }
    if (value.__t === "geopoint") {
      return new GeoPoint(value.latitude, value.longitude);
    }
    if (value.__t === "reference") {
      return db.doc(value.path);
    }
    if (value.__t === "bytes") {
      return Buffer.from(value.base64, "base64");
    }
    const out = {};
    for (const key of Object.keys(value)) {
      out[key] = fromPortable(value[key], types, db);
    }
    return out;
  }
  return value;
}

module.exports = { toPortable, fromPortable };
