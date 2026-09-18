"use strict";

// Wraps a Firestore instance so that export code CANNOT write, no matter
// what it's ever changed to do -- a code-level guarantee that backs up the
// IAM-level one (the export credential should also only hold
// roles/datastore.viewer; see docs/BACKUP_RESTORE.md). If a future edit to
// export_firestore.js/tree.js ever adds a write call by mistake, this
// throws immediately instead of silently succeeding against whatever
// project the credential happens to have write access to.
//
// Blocks the mutating surface at every level a script could reach it from:
//   - db.batch()/db.bulkWriter()/db.runTransaction()/db.recursiveDelete()
//   - .set/.update/.delete/.create/.add on any collection or document
//     reference obtained through the wrapped db
//   - every ROUTE by which a script can obtain a *fresh* reference from one
//     already in hand, so a write method reached that way is blocked too:
//     .doc()/.collection()/.collectionGroup(), .parent, .withConverter(),
//     and -- this is the one tree.js's own traversal actually depends on --
//     .listDocuments()/.listCollections(), which return arrays of brand new
//     reference objects. Missing that last one meant every document and
//     subcollection below the first explicit .collection() call was
//     unwrapped and fully writable: tree.js's recursion walks the whole
//     archive using exactly those two methods (see its own header comment),
//     so the guard was protecting only the top level in practice.
//
// Audit of @google-cloud/firestore's Firestore class (node_modules/
// @google-cloud/firestore/build/src/index.js) for every public, non-
// underscore method: doc/collection/collectionGroup (ref factories, wrapped
// below), batch/bulkWriter/runTransaction/recursiveDelete (writes, blocked
// below), listCollections/getAll (reads, getAll ALSO needs snapshot
// wrapping -- see below), settings/toJSON (client configuration/
// introspection, not data), terminate (closes the connection, writes
// nothing). Internal (`_`-prefixed) methods such as _recursiveDelete,
// _retry, _initializeStream, request/requestStream are unreachable from
// outside this class except through the public entry points above -- they
// call `this.<method>()` against the real unwrapped instance directly, so
// they were never something a Proxy on an external reference could have
// intercepted, and blocking the public entry point (e.g. recursiveDelete)
// is what actually matters. That audit covered the Firestore class only --
// see the two escapes below, both found in review, which came from the
// DocumentReference/Query/DocumentSnapshot/QuerySnapshot classes instead.
//
// A second escape: `.get()` (on a document OR a query/collection),
// `.stream()`, and `Firestore.prototype.getAll()` all resolve to a
// DocumentSnapshot/QuerySnapshot -- and every one of those has a `.ref`
// (or, for a QuerySnapshot, a `.docs` array of snapshots each with their
// own `.ref`, and a `.docChanges()` array of changes each with their own
// `.doc.ref`) that the SDK built from the RAW target, not the Proxy:
// DocumentSnapshot's `get ref()` returns `this._ref` verbatim
// (node_modules/@google-cloud/firestore/build/src/document.js), and
// `.get()`'s own implementation calls `this._firestore.getAll(this)` where
// `this` is always the unwrapped object once a method has been handed out
// via `.bind(target)`. Without the wrapping below, `snap.ref.set(...)` was
// a live, fully-writable escape -- and `doc.ref` from a `.get()` result is
// the textbook idiom for "write back to what I just read," making it the
// single most likely thing a future contributor reaches for by accident.
// tree.js's own exportCollection() calls `docRef.get()` on every document
// it processes, so an unwrapped-`.ref` snapshot already existed in memory
// on every export run before this fix -- nothing exploited it only because
// nothing in tree.js happens to read `.ref` off a snapshot today.
// `docChanges()` returns a populated array on any one-shot `.get()`, not
// only on a realtime listener's snapshot -- it is wrapped here for that
// reason, even though nothing in this tool calls it today either.
//
// A third escape, also found in review: every wrapped reference and every
// wrapped snapshot's `.ref` still hands out the RAW, unwrapped root
// Firestore instance through its own `.firestore` back-pointer (and a
// QuerySnapshot's `.query` back-pointer resolves the raw, unwrapped Query
// the same way) -- both are plain property getters, not in any "returns a
// fresh reference" list above, so they fell through untouched. From there,
// `ref.firestore.collection(...).doc(...).set(...)` -- or even
// `ref.firestore.batch()`, reopening the exact surface BLOCKED_DB_METHODS
// exists to close -- was a live write path. Both are guarded below the
// same way `.parent` already was: by re-wrapping whatever they resolve to
// before handing it back.

const BLOCKED_DB_METHODS = ["batch", "bulkWriter", "runTransaction", "recursiveDelete"];
const BLOCKED_REF_METHODS = ["set", "update", "delete", "create", "add"];

// Methods that hand back a single fresh reference/query, requiring the
// wrapper to re-wrap that return value before handing it to the caller.
const REF_RETURNING_METHODS = new Set(["doc", "collection", "withConverter"]);
// Methods that hand back an ARRAY of fresh references -- the actual
// traversal primitives tree.js uses for every level below the top one.
const REF_ARRAY_RETURNING_METHODS = new Set(["listDocuments", "listCollections"]);
// `.get()` on a DocumentReference resolves a DocumentSnapshot; on a
// CollectionReference/Query/CollectionGroup it resolves a QuerySnapshot.
// wrapSnapshot() below handles either shape generically.
const SNAPSHOT_RETURNING_METHODS = new Set(["get"]);
// `.stream()` exists only on CollectionReference/Query/CollectionGroup, and
// emits a live stream of QueryDocumentSnapshot objects rather than
// resolving a single value.
const STREAM_RETURNING_METHODS = new Set(["stream"]);

const { Transform } = require("node:stream");

/**
 * Wraps a DocumentSnapshot or QuerySnapshot so every reference it can hand
 * back -- `.ref`; for a QuerySnapshot, every `.docs[i].ref`, every snapshot
 * handed to `.forEach()`, and every `.docChanges()[i].doc.ref`; and a
 * QuerySnapshot's own `.query` back-pointer -- is a guarded reference, not
 * the raw, fully-writable one the SDK built internally. `onSnapshot` (a
 * realtime listener) is the only thing genuinely out of scope: this tool
 * never opens one, only ever calls `.get()`/`.stream()`/`getAll()` -- but
 * `docChanges()` is populated on a one-shot `.get()` too, so it is
 * wrapped, not skipped. (QuerySnapshot has no `[Symbol.iterator]` in the
 * real SDK -- `for...of` over one throws "QuerySnapshot is not iterable"
 * before this wrapper is ever consulted, so there is deliberately no
 * iterator handling here to go with it.)
 */
function wrapSnapshot(snap) {
  if (snap === null || snap === undefined) return snap;
  return new Proxy(snap, {
    get(target, prop, receiver) {
      if (prop === "ref" || prop === "query") {
        const value = Reflect.get(target, prop, receiver);
        return value ? wrapRef(value) : value;
      }
      if (prop === "doc") {
        // DocumentChange's `.doc` (see docChanges() below) -- a property,
        // not a method, so it's handled here rather than in the function
        // branch beneath.
        const doc = Reflect.get(target, prop, receiver);
        return doc ? wrapSnapshot(doc) : doc;
      }
      if (prop === "docs") {
        const docs = Reflect.get(target, prop, receiver);
        return Array.isArray(docs) ? docs.map((d) => wrapSnapshot(d)) : docs;
      }
      const value = Reflect.get(target, prop, receiver);
      if (typeof value !== "function") return value;
      if (prop === "forEach") {
        return (callback, thisArg) => value.call(target, (doc) => callback.call(thisArg, wrapSnapshot(doc)));
      }
      if (prop === "docChanges") {
        return (...args) => value.apply(target, args).map((change) => wrapSnapshot(change));
      }
      return value.bind(target);
    },
  });
}

/** Pipes a raw `.stream()` of snapshots through a wrapped copy of each one. */
function wrapDocStream(rawStream) {
  const transform = new Transform({
    objectMode: true,
    transform(chunk, _enc, callback) {
      callback(null, wrapSnapshot(chunk));
    },
  });
  rawStream.on("error", (err) => transform.emit("error", err));
  rawStream.pipe(transform);
  return transform;
}

function blocked(methodName) {
  return () => {
    throw new Error(
      `Read-only Firestore guard: "${methodName}" is blocked. The export tool ` +
        "must never write to its source project."
    );
  };
}

function wrapRef(ref) {
  return new Proxy(ref, {
    get(target, prop, receiver) {
      if (typeof prop === "string" && BLOCKED_REF_METHODS.includes(prop)) {
        return blocked(prop);
      }
      const value = Reflect.get(target, prop, receiver);
      // `.parent` and `.firestore` are getters, not methods: `.parent`
      // returns an already-built reference (a CollectionReference from a
      // document, or the parent DocumentReference of a nested collection,
      // or null at the root); `.firestore` returns the root Firestore
      // instance every reference carries a back-pointer to. Both have to
      // be re-wrapped here rather than in the function branch below, or
      // either hands back something fully writable.
      if (prop === "parent") {
        return value ? wrapRef(value) : value;
      }
      if (prop === "firestore") {
        return value ? makeReadOnlyFirestore(value) : value;
      }
      if (typeof value !== "function") return value;
      if (REF_RETURNING_METHODS.has(prop)) {
        return (...args) => wrapRef(value.apply(target, args));
      }
      if (REF_ARRAY_RETURNING_METHODS.has(prop)) {
        return async (...args) => {
          const refs = await value.apply(target, args);
          return refs.map((r) => wrapRef(r));
        };
      }
      if (SNAPSHOT_RETURNING_METHODS.has(prop)) {
        return (...args) => value.apply(target, args).then((snap) => wrapSnapshot(snap));
      }
      if (STREAM_RETURNING_METHODS.has(prop)) {
        return (...args) => wrapDocStream(value.apply(target, args));
      }
      return value.bind(target);
    },
  });
}

function makeReadOnlyFirestore(db) {
  return new Proxy(db, {
    get(target, prop, receiver) {
      if (typeof prop === "string" && BLOCKED_DB_METHODS.includes(prop)) {
        return blocked(prop);
      }
      const value = Reflect.get(target, prop, receiver);
      if (typeof value !== "function") return value;
      if (prop === "doc" || prop === "collection" || prop === "collectionGroup") {
        return (...args) => wrapRef(value.apply(target, args));
      }
      if (prop === "listCollections") {
        return async (...args) => {
          const refs = await value.apply(target, args);
          return refs.map((r) => wrapRef(r));
        };
      }
      if (prop === "getAll") {
        return async (...args) => {
          const snaps = await value.apply(target, args);
          return snaps.map((s) => wrapSnapshot(s));
        };
      }
      return value.bind(target);
    },
  });
}

module.exports = { makeReadOnlyFirestore };
