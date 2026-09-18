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
// db.batch()/db.bulkWriter()/db.runTransaction(), and .set/.update/.delete/
// .create/.add on any collection or document reference obtained through the
// wrapped db (including nested ones, via .doc()/.collection() themselves
// returning wrapped references).

const BLOCKED_DB_METHODS = ["batch", "bulkWriter", "runTransaction"];
const BLOCKED_REF_METHODS = ["set", "update", "delete", "create", "add"];

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
      if (typeof value !== "function") return value;
      if (prop === "doc" || prop === "collection") {
        return (...args) => wrapRef(value.apply(target, args));
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
      return value.bind(target);
    },
  });
}

module.exports = { makeReadOnlyFirestore };
