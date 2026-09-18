"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { Readable } = require("node:stream");
const { makeReadOnlyFirestore } = require("../src/read_only_db");

// A minimal fake that shapes itself like the pieces of the Admin SDK's
// Firestore/CollectionReference/DocumentReference this tool actually calls
// (plus the ones this guard must ALSO cover: recursiveDelete, listDocuments,
// listCollections, parent, withConverter, and -- the escape found in review
// -- get()/stream()/getAll(), whose resolved snapshot(s) carry a `.ref` the
// real SDK builds from the raw, unwrapped target), so this test needs no
// real Firestore instance or emulator.
//
// `.get()` resolves to a fake DocumentSnapshot whose `.ref` is `ref` itself
// (the same raw object `wrapRef` was given) -- this is exactly the shape
// that made the real bug possible: the snapshot's reference is built from
// whatever raw object happened to receive the call, regardless of how the
// caller reached it.
function fakeDocRef(id, parentCollection) {
  const ref = {
    id,
    set: () => "wrote",
    update: () => "wrote",
    delete: () => "wrote",
    create: () => "wrote",
    get: async () => ({ id, exists: true, ref, data: () => ({ x: 1 }) }),
    withConverter: () => fakeDocRef(`${id}-converted`, parentCollection),
    collection: (subId) => fakeCollectionRef(subId, ref),
    // A document's subcollections, discovered the same way tree.js
    // discovers them -- this is the array the read-only wrapper must also
    // wrap, since tree.js recurses into exactly these results.
    listCollections: async () => [fakeCollectionRef("sub-a", ref), fakeCollectionRef("sub-b", ref)],
  };
  Object.defineProperty(ref, "parent", { get: () => parentCollection ?? null });
  return ref;
}
function fakeCollectionRef(id, parentDoc) {
  const ref = {
    id,
    add: () => "wrote",
    doc: (docId) => fakeDocRef(docId, ref),
    withConverter: () => fakeCollectionRef(`${id}-converted`, parentDoc),
    // The array of document refs tree.js's exportCollection() actually
    // walks -- see the comment on REF_ARRAY_RETURNING_METHODS.
    listDocuments: async () => [fakeDocRef("d1", ref), fakeDocRef("d2", ref)],
    // A fake QuerySnapshot: `.docs`, `.forEach()`, and direct iteration all
    // hand out doc snapshots whose `.ref` is the raw underlying doc ref.
    get: async () => {
      const docs = [fakeDocRef("qd1", ref), fakeDocRef("qd2", ref)].map((docRef) => ({
        id: docRef.id, exists: true, ref: docRef, data: () => ({ x: 1 }),
      }));
      return {
        docs,
        forEach(cb) { docs.forEach(cb); },
        [Symbol.iterator]() { return docs[Symbol.iterator](); },
      };
    },
    // A fake `.stream()`: a real Node Readable (object mode), exactly as
    // the SDK returns, emitting the same raw-ref-carrying snapshot shape.
    stream: () => {
      const docs = [fakeDocRef("sd1", ref), fakeDocRef("sd2", ref)].map((docRef) => ({
        id: docRef.id, exists: true, ref: docRef, data: () => ({ x: 1 }),
      }));
      return Readable.from(docs, { objectMode: true });
    },
  };
  Object.defineProperty(ref, "parent", { get: () => parentDoc ?? null });
  return ref;
}
function fakeDb() {
  const docA = fakeDocRef("a");
  const docB = fakeDocRef("b");
  return {
    batch: () => "wrote",
    bulkWriter: () => "wrote",
    runTransaction: () => "wrote",
    recursiveDelete: () => "wrote",
    listCollections: async () => [fakeCollectionRef("top-a"), fakeCollectionRef("top-b")],
    collection: (id) => fakeCollectionRef(id),
    doc: (path) => (path === "a" ? docA : path === "b" ? docB : fakeDocRef(path)),
    // Mirrors the real Firestore.prototype.getAll(...refs): resolves an
    // array of snapshots, one per ref passed in, each carrying the raw
    // ref -- exactly the same escape shape as .get()/.stream().
    getAll: async (...refs) => refs.map((r) => ({ id: r.id, exists: true, ref: r, data: () => ({}) })),
  };
}

test("blocks db.batch/bulkWriter/runTransaction/recursiveDelete", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  assert.throws(() => db.batch(), /Read-only Firestore guard/);
  assert.throws(() => db.bulkWriter(), /Read-only Firestore guard/);
  assert.throws(() => db.runTransaction(), /Read-only Firestore guard/);
  assert.throws(() => db.recursiveDelete({}), /Read-only Firestore guard/);
});

test('recursiveDelete throws before reaching the SDK -- the fake never runs, only the guard does', () => {
  const inner = fakeDb();
  let recursiveDeleteWasCalled = false;
  inner.recursiveDelete = () => {
    recursiveDeleteWasCalled = true;
    return "wrote";
  };
  const db = makeReadOnlyFirestore(inner);
  assert.throws(() => db.recursiveDelete(db.collection("users")), /Read-only Firestore guard/);
  assert.equal(recursiveDeleteWasCalled, false, "the guard must throw BEFORE the real method ever runs");
});

test("allows read methods straight through", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const snap = await db.collection("x").doc("y").get();
  assert.equal(snap.exists, true);
  assert.deepEqual(snap.data(), { x: 1 });
});

test("blocks set/update/delete/create on a document reached via db.collection().doc()", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const doc = db.collection("users").doc("u1");
  assert.throws(() => doc.set({}), /Read-only Firestore guard/);
  assert.throws(() => doc.update({}), /Read-only Firestore guard/);
  assert.throws(() => doc.delete(), /Read-only Firestore guard/);
  assert.throws(() => doc.create({}), /Read-only Firestore guard/);
  const snap = await doc.get();
  assert.equal(snap.exists, true);
});

test("blocks add() on a collection reference reached via db.doc().collection()", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const nested = db.doc("users/u1").collection("attempts");
  assert.throws(() => nested.add({}), /Read-only Firestore guard/);
});

test("blocks writes arbitrarily deep, not just one level of nesting", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const deep = db.collection("a").doc("b").collection("c").doc("d");
  assert.throws(() => deep.set({}), /Read-only Firestore guard/);
});

test("blocked methods still identify themselves in the error", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  assert.throws(() => db.collection("x").doc("y").update({}), /"update"/);
});

test("a document ref obtained via collection.listDocuments() is still guarded -- tree.js's own traversal path", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const docs = await db.collection("attempts").listDocuments();
  assert.equal(docs.length, 2);
  for (const doc of docs) {
    assert.throws(() => doc.set({}), /Read-only Firestore guard/);
    assert.throws(() => doc.delete(), /Read-only Firestore guard/);
  }
});

test("a collection ref obtained via document.listCollections() is still guarded -- tree.js's own traversal path", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const doc = db.collection("attempts").doc("uid1");
  const subcollections = await doc.listCollections();
  assert.equal(subcollections.length, 2);
  for (const sub of subcollections) {
    assert.throws(() => sub.add({}), /Read-only Firestore guard/);
    // And the guard survives another level down through that subcollection.
    assert.throws(() => sub.doc("x").set({}), /Read-only Firestore guard/);
  }
});

test("refs found several listDocuments()/listCollections() hops deep are still guarded", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const [doc] = await db.collection("attempts").listDocuments();
  const [sub] = await doc.listCollections();
  const [nestedDoc] = await sub.listDocuments();
  assert.throws(() => nestedDoc.set({}), /Read-only Firestore guard/);
});

test("db.listCollections() results are guarded too", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const [top] = await db.listCollections();
  assert.throws(() => top.add({}), /Read-only Firestore guard/);
  assert.throws(() => top.doc("x").set({}), /Read-only Firestore guard/);
});

test("a ref's .parent is guarded", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const doc = db.collection("users").doc("u1");
  const parentCollection = doc.parent;
  assert.throws(() => parentCollection.add({}), /Read-only Firestore guard/);

  const nestedDoc = parentCollection.doc("u2");
  const grandparent = nestedDoc.parent;
  assert.throws(() => grandparent.add({}), /Read-only Firestore guard/);
});

test("a ref returned by .withConverter() is still guarded", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const converted = db.collection("users").doc("u1").withConverter({});
  assert.throws(() => converted.set({}), /Read-only Firestore guard/);
});

// --- the escape found in review: snapshot.ref -------------------------------
// .get()/.stream()/getAll() all resolve DocumentSnapshot/QuerySnapshot
// objects whose `.ref` the real SDK builds from the raw target, not
// whatever wrapped the call. See src/read_only_db.js's header comment for
// the full story and the live-emulator repro that first found this.

test("a doc snapshot's .ref (from a wrapped doc's .get()) is guarded", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const snap = await db.collection("users").doc("u1").get();
  assert.equal(snap.exists, true);
  assert.deepEqual(snap.data(), { x: 1 });
  assert.throws(() => snap.ref.set({}), /Read-only Firestore guard/);
  assert.throws(() => snap.ref.update({}), /Read-only Firestore guard/);
  assert.throws(() => snap.ref.delete(), /Read-only Firestore guard/);
});

test("a query snapshot's .docs[i].ref (from a wrapped collection's .get()) is guarded", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const query = await db.collection("users").get();
  assert.equal(query.docs.length, 2);
  for (const doc of query.docs) {
    assert.throws(() => doc.ref.set({}), /Read-only Firestore guard/);
  }
});

test("a query snapshot's .forEach() hands out guarded snapshots", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const query = await db.collection("users").get();
  let seen = 0;
  query.forEach((doc) => {
    seen += 1;
    assert.throws(() => doc.ref.set({}), /Read-only Firestore guard/);
  });
  assert.equal(seen, 2);
});

test("iterating a query snapshot directly (for...of) hands out guarded snapshots", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const query = await db.collection("users").get();
  let seen = 0;
  for (const doc of query) {
    seen += 1;
    assert.throws(() => doc.ref.set({}), /Read-only Firestore guard/);
  }
  assert.equal(seen, 2);
});

test("a snapshot emitted by .stream() is guarded", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const stream = db.collection("users").stream();
  const seen = [];
  for await (const doc of stream) {
    seen.push(doc);
    assert.throws(() => doc.ref.set({}), /Read-only Firestore guard/);
  }
  assert.equal(seen.length, 2);
});

test("db.getAll() results are guarded, even when passed already-wrapped refs", async () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const a = db.doc("a");
  const b = db.doc("b");
  const [snapA, snapB] = await db.getAll(a, b);
  assert.throws(() => snapA.ref.set({}), /Read-only Firestore guard/);
  assert.throws(() => snapB.ref.set({}), /Read-only Firestore guard/);
});
