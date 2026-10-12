import { before, beforeEach, after, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, collection, query, where, limit, getDoc, getDocs, setDoc, updateDoc, deleteDoc, writeBatch, arrayUnion, arrayRemove, serverTimestamp, runTransaction } from 'firebase/firestore';

let env;
const groupPath = 'squads/sq_uma';
const squad = {
  squadId: 'sq_uma', squadCode: 'PUJA7K9X', name: 'Uma group',
  hostId: 'host', hostName: 'Host', membersUid: ['host', 'member'],
  chosenPandals: [], isHoppingActive: false, activeStopIndex: 0, planRevision: 0,
  meetupPointName: 'Metro', meetupLat: 22.57, meetupLng: 88.36,
  separationThresholdMeters: 500, lastMessage: 'Welcome', lastMessageTime: 1,
};
const member = (uid, isHost = false) => ({
  id: uid, name: uid, lat: 22.57, lng: 88.36, status: 'Active',
  photo_url: '', phone_number: '', is_host: isHost, is_user: true,
  share_location: true, is_online: true, battery: 90, batteryLevel: 90,
  color: 4294947584, last_seen: 1,
});
const message = (id, senderId = 'member') => ({
  id, squadId: 'sq_uma', senderId, senderName: senderId, senderPhotoUrl: '',
  type: 'text', text: 'Hello', mediaUrl: '', media_url: '', thumbnailUrl: '', timestamp: 2,
});
const dbFor = (uid) => env.authenticatedContext(uid).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-uma-rules',
    firestore: { rules: await readFile(new URL('android-v1.0.0.firestore.rules', import.meta.url), 'utf8') },
  });
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, groupPath), squad);
    await setDoc(doc(db, `${groupPath}/members/host`), member('host', true));
    await setDoc(doc(db, `${groupPath}/members/member`), member('member'));
    await setDoc(doc(db, 'pandals/p1'), { name: 'Pandal' });
  });
});
after(async () => { await env?.cleanup(); });

test('public pandal browsing works; client writes remain denied', async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(db, 'pandals/p1')));
  await assertSucceeds(getDocs(collection(db, 'pandals')));
  await assertFails(setDoc(doc(dbFor('host'), 'pandals/p1'), { name: 'Changed' }));
});

test('Android shared-plan transaction succeeds for members', async () => {
  const db = dbFor('member');
  await assertSucceeds(runTransaction(db, async (tx) => {
    const ref = doc(db, groupPath);
    const snapshot = await tx.get(ref);
    tx.update(ref, {
      chosenPandals: [{ id: 'p1', name: 'Pandal', isVisited: false }],
      isHoppingActive: true, activeStopIndex: 0,
      planRevision: snapshot.data().planRevision + 1, updatedAt: serverTimestamp(),
    });
  }));
  await assertFails(updateDoc(doc(dbFor('outsider'), groupPath), { chosenPandals: [] }));
});

test('Android queue reports and estimates retain their release permissions', async () => {
  const db = dbFor('member');
  const reportPath = `${groupPath}/queue_reports/p1_member_2`;
  await assertSucceeds(setDoc(doc(db, reportPath), {
    pandalId: 'p1', waitMinutes: 15, timestamp: 2, reporterId: 'member', source: 'squad',
  }));
  await assertSucceeds(getDocs(collection(db, `${groupPath}/queue_reports`)));
  await assertFails(getDoc(doc(dbFor('outsider'), reportPath)));
  await assertFails(setDoc(doc(dbFor('outsider'), `${groupPath}/queue_reports/forged`), { reporterId: 'outsider' }));
  await assertFails(setDoc(doc(db, `${groupPath}/queue_reports/forged`), { reporterId: 'host' }));
  await assertFails(updateDoc(doc(db, reportPath), { waitMinutes: 0 }));
  const estimatePath = 'pandal_queue_waits/p1';
  await assertSucceeds(setDoc(doc(db, estimatePath), {
    estimated_wait_minutes: 15, confidence: 'medium', trend: 'stable',
    report_count: 1, user_reports: 1, squad_reports: 0, public_reports: 0,
    last_updated: serverTimestamp(), updated_at: serverTimestamp(),
  }, { merge: true }));
  await assertSucceeds(getDoc(doc(dbFor('outsider'), estimatePath)));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), estimatePath)));
});

test('iOS group/host batch followed by welcome notice matches Android rules', async () => {
  const db = dbFor('creator');
  const batch = writeBatch(db);
  batch.set(doc(db, 'squads/new'), { ...squad, squadId: 'new', hostId: 'creator', membersUid: ['creator'] });
  batch.set(doc(db, 'squads/new/members/creator'), member('creator', true));
  await assertSucceeds(batch.commit());
  await assertSucceeds(setDoc(doc(db, 'squads/new/messages/welcome_new'), { ...message('welcome_new', 'system_pujo'), squadId: 'new' }));
});

test('Android sequential group creation accepts the release document shape', async () => {
  const db = dbFor('creator');
  await assertSucceeds(setDoc(doc(db, 'squads/new'), { ...squad, hostId: 'creator', membersUid: ['creator'] }));
  await assertSucceeds(setDoc(doc(db, 'squads/new/members/creator'), member('creator', true)));
  await assertSucceeds(setDoc(doc(db, 'squads/new/messages/welcome_new'), { ...message('welcome_new', 'system_pujo'), squadId: 'new' }));
});

test('iOS membership batch then notice and sequential Android joins work', async () => {
  const db = dbFor('joiner');
  const batch = writeBatch(db);
  batch.update(doc(db, groupPath), { membersUid: arrayUnion('joiner') });
  batch.set(doc(db, `${groupPath}/members/joiner`), member('joiner'));
  await assertSucceeds(batch.commit());
  await assertSucceeds(setDoc(doc(db, `${groupPath}/messages/join_joiner_2`), message('join_joiner_2', 'system_pujo')));
  const android = dbFor('android');
  await assertSucceeds(updateDoc(doc(android, groupPath), { membersUid: arrayUnion('android') }));
  await assertSucceeds(setDoc(doc(android, `${groupPath}/members/android`), member('android'), { merge: true }));
  await assertSucceeds(setDoc(doc(android, `${groupPath}/messages/join_android_2`), message('join_android_2', 'system_pujo')));
});

test('iOS atomic leave accepts member deletion, notice and membership removal', async () => {
  const db = dbFor('member');
  const batch = writeBatch(db);
  batch.delete(doc(db, `${groupPath}/members/member`));
  batch.set(doc(db, `${groupPath}/messages/leave_member_2`), message('leave_member_2', 'system_pujo'));
  batch.update(doc(db, groupPath), { membersUid: arrayRemove('member') });
  await assertSucceeds(batch.commit());
  await assertFails(getDoc(doc(db, `${groupPath}/members/host`)));
});

test('Android v1.0.0 leave notice followed by delete/remove batch works', async () => {
  const db = dbFor('member');
  await assertSucceeds(setDoc(doc(db, `${groupPath}/messages/leave_member_2`), message('leave_member_2', 'system_pujo')));
  const batch = writeBatch(db);
  batch.delete(doc(db, `${groupPath}/members/member`));
  batch.update(doc(db, groupPath), { membersUid: arrayRemove('member') });
  await assertSucceeds(batch.commit());
});

test('member location, text and media writes work; impersonation is denied', async () => {
  const db = dbFor('member');
  await assertSucceeds(setDoc(doc(db, `${groupPath}/members/member`), { lat: 22.58, lng: 88.37, last_seen: 2, battery: 80, batteryLevel: 80 }, { merge: true }));
  await assertSucceeds(setDoc(doc(db, `${groupPath}/messages/msg_2`), message('msg_2')));
  await assertSucceeds(setDoc(doc(db, `${groupPath}/messages/media_2`), { ...message('media_2'), type: 'image', mediaUrl: 'https://example.com/photo.jpg' }));
  await assertFails(setDoc(doc(db, `${groupPath}/messages/forged`), message('forged', 'host')));
  await assertFails(updateDoc(doc(db, `${groupPath}/members/host`), { lat: 0 }));
});

test('invite-code lookup works; private roster access and membership tampering are denied', async () => {
  const db = dbFor('outsider');
  await assertSucceeds(getDocs(query(collection(db, 'squads'), where('squadCode', '==', 'PUJA7K9X'), limit(1))));
  await assertFails(getDocs(collection(db, `${groupPath}/members`)));
  await assertFails(updateDoc(doc(db, groupPath), { membersUid: ['outsider'] }));
  await assertFails(updateDoc(doc(dbFor('member'), groupPath), { hostId: 'member' }));
  await assertFails(deleteDoc(doc(dbFor('host'), groupPath)));
});

// Guard the write sequencing: Android authorizes notices against membership
// before the batch, so a notice cannot be included in the initial create/join.
test('welcome notice inside the initial group batch is rejected', async () => {
  const db = dbFor('creator');
  const batch = writeBatch(db);
  batch.set(doc(db, 'squads/new'), { ...squad, hostId: 'creator', membersUid: ['creator'] });
  batch.set(doc(db, 'squads/new/members/creator'), member('creator', true));
  batch.set(doc(db, 'squads/new/messages/welcome_new'), { ...message('welcome_new', 'system_pujo'), squadId: 'new' });
  await assertFails(batch.commit());
});

test('join notice inside the initial membership batch is rejected', async () => {
  const db = dbFor('joiner');
  const batch = writeBatch(db);
  batch.update(doc(db, groupPath), { membersUid: arrayUnion('joiner') });
  batch.set(doc(db, `${groupPath}/members/joiner`), member('joiner'));
  batch.set(doc(db, `${groupPath}/messages/join_joiner_2`), message('join_joiner_2', 'system_pujo'));
  await assertFails(batch.commit());
});
