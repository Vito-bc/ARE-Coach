"use strict";

const { toPortable, fromPortable } = require("./serialize");

// Firestore lets a document exist purely as a parent for a subcollection,
// with no fields of its own (this app relies on that: attempts/{uid} itself
// is never written, only attempts/{uid}/sessions/{id} is -- see
// functions/index.js's deleteAccount, which recursiveDeletes attempts/{uid}
// as a tree without ever having created the doc). `collection.listDocuments()`
// returns references for those parent-only documents too, which is exactly
// why it's used here instead of `collection.get()` (a query, which only
// returns documents that exist).

function sortById(refs) {
  return [...refs].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

/**
 * Recursively reads one collection (and everything under every document in
 * it) into a plain, JSON-serializable tree. Read-only: only .listDocuments(),
 * .get() and .listCollections() are called.
 *
 * Shape per document id:
 *   { exists: boolean, data: <portable JSON> | null, subcollections: { [id]: <same shape> } }
 */
async function exportCollection(collRef, types) {
  const docRefs = sortById(await collRef.listDocuments());
  const out = {};
  for (const docRef of docRefs) {
    const snap = await docRef.get();
    const subcolRefs = sortById(await docRef.listCollections());
    const subcollections = {};
    for (const subcolRef of subcolRefs) {
      subcollections[subcolRef.id] = await exportCollection(subcolRef, types);
    }
    out[docRef.id] = {
      exists: snap.exists,
      data: snap.exists ? toPortable(snap.data(), types) : null,
      subcollections,
    };
  }
  return out;
}

/**
 * Reads every collection in `collectionIds` under `db`.
 * Returns { [collectionId]: <exportCollection tree> }.
 */
async function exportAll(db, collectionIds, types) {
  const out = {};
  for (const name of collectionIds) {
    out[name] = await exportCollection(db.collection(name), types);
  }
  return out;
}

/**
 * Recursively writes a tree produced by exportCollection back into `collRef`
 * on the TARGET database `db`. A document is only .set() when it actually
 * existed at export time (see the parent-only-document note above) -- an
 * empty parent should stay unwritten on restore just as it was on the
 * source, not be fabricated with an empty {} body.
 *
 * .set() (no merge) fully replaces each restored document's contents, so a
 * document is byte-for-byte what the archive says. It does NOT delete
 * documents at the target that aren't in the archive -- restore into an
 * empty/fresh project for a true disaster-recovery restore (see
 * docs/BACKUP_RESTORE.md).
 */
async function restoreCollection(db, collRef, tree, types) {
  for (const id of Object.keys(tree)) {
    const node = tree[id];
    const docRef = collRef.doc(id);
    if (node.exists) {
      await docRef.set(fromPortable(node.data, types, db));
    }
    for (const subId of Object.keys(node.subcollections || {})) {
      await restoreCollection(db, docRef.collection(subId), node.subcollections[subId], types);
    }
  }
}

async function restoreAll(db, archive, types) {
  for (const name of Object.keys(archive)) {
    await restoreCollection(db, db.collection(name), archive[name], types);
  }
}

/** Counts documents that `exists: true` in a tree, at every depth. */
function countExisting(tree) {
  let n = 0;
  for (const id of Object.keys(tree)) {
    const node = tree[id];
    if (node.exists) n += 1;
    for (const subId of Object.keys(node.subcollections || {})) {
      n += countExisting(node.subcollections[subId]);
    }
  }
  return n;
}

module.exports = { exportCollection, exportAll, restoreCollection, restoreAll, countExisting };
