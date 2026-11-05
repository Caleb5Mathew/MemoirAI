// Run against a local Firestore emulator with @firebase/rules-unit-testing installed.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, serverTimestamp } = require('firebase/firestore');
const { createStorybookJobHandler, settleStorybookReservation } = require('./storybookAdmission');

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost || !/^(127\.0\.0\.1|localhost):\d+$/.test(emulatorHost)) {
  throw new Error('This regression test requires a local FIRESTORE_EMULATOR_HOST.');
}
const [host, port] = emulatorHost.split(':');
const projectId = 'demo-memoir-security';

test('legacy clients cannot forge admission or server refund provenance; real admission and refunds work', async () => {
  const env = await initializeTestEnvironment({ projectId, firestore: {
    host, port:Number(port), rules:fs.readFileSync(path.join(__dirname,'../firestore.rules'),'utf8')
  } });
  const admin = require('firebase-admin');
  const app = admin.initializeApp({projectId},'storybook-rules-regression');
  const db = app.firestore();
  try {
    await env.clearFirestore();
    const userId='rules-owner';
    const client=env.authenticatedContext(userId).firestore();
    const legacy=doc(client,`users/${userId}/storybookJobs/legacy`);
    await assertSucceeds(setDoc(legacy,{status:'queued',clientVersion:0}));
    await assertSucceeds(updateDoc(legacy,{clientVersion:1}));
    await assertFails(updateDoc(legacy,{admissionVersion:1,requestHash:'a'.repeat(64),reservationState:'reserved',serverFailureSource:'worker'}));
    await assertFails(setDoc(doc(client,`users/${userId}/storybookJobs/forged`),{admissionVersion:1,status:'queued'}));

    class HttpsError extends Error { constructor(code,message){super(message);this.code=code;} }
    const handler=createStorybookJobHandler({db,HttpsError,
      serverTimestamp:()=>admin.firestore.FieldValue.serverTimestamp(),
      timestampFromDate:date=>admin.firestore.Timestamp.fromDate(date),
      fetchImpl:async()=>({ok:true,json:async()=>({subscriber:{entitlements:{image_generation:{expires_date:'2099-01-01T00:00:00Z'}}}})})
    });
    const jobId='server-admitted';
    await handler({auth:{uid:userId},data:{jobId,job:{
      profileId:'11111111-1111-4111-8111-111111111111',bookVersionId:jobId,pageCountTarget:2,
      pinnedMemoryIds:['22222222-2222-4222-8222-222222222222'],clientVersion:2,
      profileName:'Test',artStyle:'kidsBook',serverFailureSource:'worker'
    }}});
    const job=db.doc(`users/${userId}/storybookJobs/${jobId}`);
    const admitted=(await job.get()).data();
    assert.equal(admitted.admissionVersion,1);assert.equal(admitted.serverFailureSource,null);
    await job.update({status:'aiComplete',memoryResults:{one:{illustrationStoragePath:'test/one.png'}},progress:{completedMemoryCount:1}});
    const clientJob=doc(client,job.path);
    await assertFails(updateDoc(clientJob,{status:'failed',error:'forged refund',updatedAt:serverTimestamp(),serverFailureSource:'worker'}));
    await assertSucceeds(updateDoc(clientJob,{status:'failed',error:'client finalization failed',updatedAt:serverTimestamp()}));
    const settle=()=>settleStorybookReservation({db,jobRef:job,userId,serverTimestamp:()=>admin.firestore.FieldValue.serverTimestamp()});
    assert.deepEqual(await settle(),{status:'settled',userPages:1,globalPages:1});
    const usage=db.doc(`users/${userId}/aiUsage/${admitted.usageDocumentId}`);
    assert.equal((await usage.get()).data().reservedPages,1);
    await job.update({serverFailureSource:'worker'});
    assert.deepEqual(await settle(),{status:'refunded',userPages:0,globalPages:1});
    assert.equal((await usage.get()).data().reservedPages,0);
    assert.equal((await settle()).status,'already-settled');
    assert.equal((await usage.get()).data().reservedPages,0);
  } finally { await app.delete();await env.cleanup(); }
});
