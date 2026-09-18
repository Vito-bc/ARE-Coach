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
// Full audit of @google-cloud/firestore's Firestore class (node_modules/
// @google-cloud/firestore/build/src/index.js) for every public, non-
// underscore method: doc/collection/collectionGroup (ref factories, wrapped
// below), batch/bulkWriter/runTransaction/recursiveDelete (writes, blocked
// below), listCollections/getAll (reads), settings/toJSON (client
// configuration/introspection, not data), terminate (closes the connection,
// writes nothing). Internal (`_`-prefixed) methods such as _recursiveDelete,
// _retry, _initializeStream, request/requestStream are unreachable from
// outside this class except through the public entry points above -- they
// call `this.<method>()` against the real unwrapped instance directly, so
// they were never something a Proxy on an external reference could have
// intercepted, and blocking the public entry point (e.g. recursiveDelete)
// is what actually matters.

const BLOCKED_DB_METHODS = ["batch", "bulkWriter", "runTransaction", "recursiveDelete"];
const BLOCKED_REF_METHODS = ["set", "update", "delete", "create", "add"];

// Methods that hand back a single fresh reference/query, requiring the
// wrapper to re-wrap that return value before handing it to the caller.
const REF_RETURNING_METHODS = new Set(["doc", "collection", "withConverter"]);
// Methods that hand back an ARRAY of fresh references -- the actual
// traversal primitives tree.js uses for every level below the top one.
const REF_ARRAY_RETURNING_METHODS = new Set(["listDocuments", "listCollections"]);

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
      // `.parent` is a getter, not a method: it returns an already-built
      // reference (a CollectionReference from a document, or the parent
      // DocumentReference of a nested collection, or null at the root), so
      // it has to be re-wrapped here rather than in the function branch
      // below.
      if (prop === "parent") {
        return value ? wrapRef(value) : value;
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
      return value.bind(target);
    },
  });
}

module.exports = { makeReadOnlyFirestore };
