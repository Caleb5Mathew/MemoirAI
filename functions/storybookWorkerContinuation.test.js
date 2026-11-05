const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const timestamp = () => ({ toDate: () => new Date() });

function harness({ deadlineOnce = false, alwaysDeadline = false, retryableDeadlineOnce = false, failAfterFirstBatch = false } = {}) {
  let clock = Date.now();
  class WorkerDate extends Date { static now() { return clock; } }
  const rows = new Map();
  function apply(ref, patch, replace = false) {
    const row = replace ? {} : { ...(rows.get(ref.path) || {}) };
    for (const [key, value] of Object.entries(patch)) {
      const segments = key.split('.'); let target = row;
      for (const part of segments.slice(0, -1)) target = target[part] = { ...(target[part] || {}) };
      const leaf = segments.at(-1);
      if (value?.op === 'delete') delete target[leaf];
      else if (value?.op === 'increment') target[leaf] = (target[leaf] || 0) + value.value;
      else if (value?.op === 'union') target[leaf] = [...new Set([...(target[leaf] || []), value.value])];
      else target[leaf] = value;
    }
    rows.set(ref.path, row);
  }
  function doc(p) { return { path:p, id:p.split('/').at(-1), collection: n => collection(`${p}/${n}`),
    get: async () => snapshot(p), update: async data => apply(doc(p), data) }; }
  function snapshot(p) { const value = rows.get(p); return { id:p.split('/').at(-1), exists: value !== undefined, ref:doc(p), data:() => value }; }
  function collection(p) { return { doc:id => doc(`${p}/${id}`), where:() => collection(p), orderBy:() => collection(p), limit:() => collection(p),
    get:async () => ({ docs:[...rows.keys()].filter(key => key.startsWith(`${p}/`) && !key.slice(p.length + 1).includes('/')).map(snapshot) }) }; }
  const db = { collection, getAll:async (...refs) => Promise.all(refs.map(ref => ref.get())),
    batch:() => ({ update:()=>{}, commit:async()=>{} }),
    runTransaction:async fn => {
      const writes=[]; const result=await fn({ get:ref=>ref.get(), update:(ref,data)=>writes.push(()=>apply(ref,data)),
        set:(ref,data,options)=>writes.push(()=>apply(ref,data,!options?.merge)), delete:ref=>writes.push(()=>rows.delete(ref.path)) });
      writes.forEach(write=>write()); return result;
    } };
  const userId='user', jobId='job', profileId='00000000-0000-4000-8000-000000000001';
  const ids=Array.from({length:40},(_,i)=>`00000000-0000-4000-8000-${String(i+10).padStart(12,'0')}`);
  ids.forEach(id => rows.set(`users/user/memories/${id}`, {profileID:profileId, transcription:id, chapter:''}));
  const jobPath='users/user/storybookJobs/job', leasePath='users/user/aiUsage/storybook_active';
  rows.set(jobPath,{status:'queued',admissionVersion:1,requestHash:'a'.repeat(64),clientVersion:2,
    profileId, pageCountTarget:40,pinnedMemoryIds:ids, reservationState:'reserved',reservedPageCount:40});
  rows.set(leasePath,{admissionVersion:1,requestHash:'a'.repeat(64),jobId});
  rows.set('users/user/aiUsage/storybook_paid_test',{reservedPages:40,usedPages:0});
  const calls=new Map(); let ranks=0, ages=0, deadlineThrown=false;
  const ai={
    rankMemoriesWithLLM:async memories => {ranks++;return memories;}, extractAge:async()=>{ages++;return 10;},
    buildCastCanon:()=>({rows:[]}),loadStyleReferencePng:()=>null,
    enrichEntryCharacterDetailsFromCanon:()=>'',buildCharacterContextFromDetails:()=>'',
    extractVisualScene:async raw=>{
      if (alwaysDeadline || (failAfterFirstBatch && calls.size >= 6) || (deadlineOnce && !deadlineThrown)) {deadlineThrown=true;const e=new Error('deadline');e.code='worker-deadline';throw e;}
      return raw;
    },
    extractTitleAndCharacters:async()=>({title:'A memory'}),inferNarratorPresence:()=>({presence:'likelyAbsent'}),
    shouldAttachHeadshot:()=>({attach:false}),nameMatchesProfileFirstToken:()=>false,buildCharacterList:()=>'',
    filterCanonRowsForEntry:()=>[],assembleFinalPrompt:raw=>raw,explicitAge:()=>null,
    generateIllustrationBufferGuarded:async (_,prompt)=>{
      if (retryableDeadlineOnce && !deadlineThrown) {
        deadlineThrown=true;clock+=490_000;
        const error=new Error('Service temporarily unavailable');error.status=503;throw error;
      }
      calls.set(prompt,(calls.get(prompt)||0)+1);return Buffer.from('image');
    },
    isQuestionDrivenMemory:()=>false,generateBackCoverPitch:async()=> 'A memoir.',isUsableBackCoverPitch:()=>true
  };
  const firestore=()=>db;
  firestore.FieldValue={serverTimestamp:timestamp,delete:()=>({op:'delete'}),increment:value=>({op:'increment',value}),arrayUnion:value=>({op:'union',value})};
  firestore.Timestamp={now:timestamp,fromDate:date=>({toDate:()=>date})};
  const modules={
    'firebase-admin':{firestore},
    'firebase-functions/v2/firestore':{onDocumentCreated:(_,fn)=>fn,onDocumentUpdated:(_,fn)=>fn},
    'firebase-functions/params':{defineSecret:()=>({value:()=> 'test'})},
    'p-limit':require('p-limit'),
    './storybookAI':{createStorybookAI:()=>ai,normalizeArtStyleKey:()=> 'oil',uploadPngWithDownloadURL:async()=>({url:'https://example.invalid/image'})},
    './accountStateGuards':{assertAccountNotDeleting:async()=>{}}
  };
  const exports={};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'storybookWorker.js'),'utf8'),{
    require:name=>modules[name] || require(name),exports,Buffer,process,Date:WorkerDate,Promise,setTimeout:fn=>{ fn(); },setInterval,clearInterval,
    console:{log(){},warn(){},error(){}}
  },{filename:path.join(__dirname,'storybookWorker.js')});
  const event=()=>({params:{userId,jobId},data:snapshot(jobPath)});
  return {db,rows,jobPath,leasePath,calls,ids,event,exports,stats:()=>({ranks,ages}),
    continue:async()=>exports.continueStorybookJob({params:{userId,jobId},data:{before:{data:()=>({status:'running'})},after:snapshot(jobPath)}})};
}

test('actual worker completes forty pinned chapterless stories over durable batches without reserving again',async()=>{
  const h=harness(); await h.exports.processStorybookJob(h.event());
  assert.equal(h.rows.get(h.jobPath).status,'running_continue');
  assert.equal(h.calls.size,6); assert(h.rows.has(h.leasePath));
  const checkpoint=h.rows.get(h.jobPath);
  h.rows.set(h.jobPath,{...checkpoint,status:'running',lastHeartbeatAt:timestamp()});
  await assert.rejects(()=>h.exports.processStorybookJob(h.event()),error=>error.code==='retry-later');
  assert.equal(h.calls.size,6,'a fresh worker lease prevents duplicate provider work');
  h.rows.set(h.jobPath,checkpoint);
  const afterFirst=h.rows.get(h.jobPath);
  await h.exports.continueStorybookJob({params:{userId:'user',jobId:'job'},data:{before:{data:()=>afterFirst},after:{data:()=>afterFirst}}});
  assert.equal(h.calls.size,6,'heartbeat update must not launch another batch');
  let batches=1;
  while(h.rows.get(h.jobPath).status==='running_continue') {await h.continue();batches++;assert(batches<10);}
  assert.equal(batches,7); assert.equal(h.rows.get(h.jobPath).status,'aiComplete');
  assert.equal(h.calls.size,40); assert([...h.calls.values()].every(count=>count===1));
  assert.equal(h.rows.get(h.jobPath).progress.completedMemoryCount,40);
  assert.equal(h.stats().ages,40,'continuations must reuse age ordering');
  assert.equal(h.stats().ranks,0,'fully pinned selection does not rerank');
  assert.equal(h.rows.get('users/user/aiUsage/storybook_paid_test').reservedPages,40);
  assert(!h.rows.has(h.leasePath));
  await h.exports.processStorybookJob(h.event());
  assert.equal(h.rows.get(h.jobPath).status,'aiComplete','terminal event replay after lease release must be harmless');
  assert.equal(h.calls.size,40);
});

test('deadline defers a memory without marking failure and continuation generates it once',async()=>{
  const h=harness({deadlineOnce:true});await h.exports.processStorybookJob(h.event());
  assert.equal(h.calls.size,5);assert.equal(Object.keys(h.rows.get(h.jobPath).memoryFailures || {}).length,0);
  while(h.rows.get(h.jobPath).status==='running_continue') await h.continue();
  assert.equal(h.rows.get(h.jobPath).status,'aiComplete');assert.equal(h.calls.size,40);
  assert([...h.calls.values()].every(count=>count===1));
});

test('repeated empty deadline batches fail boundedly and release the active lease',async()=>{
  const h=harness({alwaysDeadline:true});await h.exports.processStorybookJob(h.event());
  await h.continue();await h.continue();
  assert.equal(h.rows.get(h.jobPath).status,'failed');assert(!h.rows.has(h.leasePath));assert.equal(h.calls.size,0);
});

test('stale invocation retry preserves durable successes and permanent failures',async()=>{
  const h=harness();await h.exports.processStorybookJob(h.event());
  const checkpoint=h.rows.get(h.jobPath);
  h.rows.set(h.jobPath,{...checkpoint,status:'running',workerAttemptCount:1,
    lastHeartbeatAt:{toDate:()=>new Date(0)},
    memoryFailures:{[h.ids[6]]:{stage:'image',message:'Permanent provider rejection'}},
    skippedMemoryIds:[h.ids[6]]});
  await h.exports.processStorybookJob(h.event());
  while(h.rows.get(h.jobPath).status==='running_continue') await h.continue();
  const final=h.rows.get(h.jobPath);
  assert.equal(final.status,'aiComplete');assert.equal(final.progress.completedMemoryCount,40);
  assert.equal(h.calls.size,39);assert.equal(h.calls.has(h.ids[6]),false);
  assert([...h.calls.values()].every(count=>count===1));
  assert.equal(Object.keys(final.memoryFailures).length,1);assert.equal(h.stats().ages,40);
});


test('retryable provider error at deadline defers instead of becoming a permanent failed memory',async()=>{
  const h=harness({retryableDeadlineOnce:true});await h.exports.processStorybookJob(h.event());
  assert.equal(h.rows.get(h.jobPath).status,'running_continue');
  assert.equal(Object.keys(h.rows.get(h.jobPath).memoryFailures || {}).length,0);
  let continuations=0;
  while(h.rows.get(h.jobPath).status==='running_continue') {await h.continue();assert(++continuations<10);}
  assert.equal(h.rows.get(h.jobPath).status,'aiComplete');assert.equal(h.calls.size,40);
  assert([...h.calls.values()].every(count=>count===1));
});

test('bounded continuation exhaustion finishes a usable partial book and charges only its six images',async()=>{
  const h=harness({failAfterFirstBatch:true});await h.exports.processStorybookJob(h.event());
  let continuations=0;
  while(h.rows.get(h.jobPath).status==='running_continue') {await h.continue();assert(++continuations<5);}
  const final=h.rows.get(h.jobPath);
  assert.equal(final.status,'aiComplete');assert.equal(h.calls.size,6);
  assert.equal(Object.keys(final.memoryFailures).length,34);assert.equal(final.skippedMemoryIds.length,34);
  assert.equal(final.progress.completedMemoryCount,40);
  assert(Object.values(final.memoryFailures).every(failure=>failure.code==='continuation-exhausted'));
  assert.deepEqual(require('./storybookAdmission').storybookReservationCharges(final),{userPages:6,globalPages:6});
  assert(!h.rows.has(h.leasePath));
});

test('lease renewal only extends the matching job and checkpoint preserves its reservation',async()=>{
  const h=harness();await h.exports.processStorybookJob(h.event());
  const {renewStorybookActiveLease}=require('./storybookAdmission');
  const lease=h.rows.get(h.leasePath);
  assert(lease.leaseExpiresAt.toDate()>new Date());
  assert.equal(await renewStorybookActiveLease({db:h.db,userId:'user',jobId:'other',serverTimestamp:timestamp,
    timestampFromDate:date=>({toDate:()=>date})}),false);
  assert.equal(h.rows.get(h.leasePath).jobId,'job');
  h.rows.delete(h.leasePath);
  assert.equal(await renewStorybookActiveLease({db:h.db,userId:'user',jobId:'job',serverTimestamp:timestamp,
    timestampFromDate:date=>({toDate:()=>date})}),false,'heartbeat must never recreate a released lease');
});

test('admission protects queued backlog boundedly and releases terminal or genuinely stale jobs',async()=>{
  const {isStorybookLeaseProtected,hasProtectedStorybookLease}=require('./storybookAdmission');
  const now=new Date('2026-11-05T12:00:00Z');
  const at=minutes=>({toDate:()=>new Date(now.getTime()-minutes*60_000)});
  const expired={jobId:'job',leaseExpiresAt:at(1)};
  assert.equal(isStorybookLeaseProtected(expired,{status:'running_continue',lastHeartbeatAt:at(30)},now),true);
  assert.equal(isStorybookLeaseProtected(expired,{status:'queued',createdAt:at(30)},now),true);
  assert.equal(isStorybookLeaseProtected(expired,{status:'running_continue',lastHeartbeatAt:at(46)},now),false);
  assert.equal(isStorybookLeaseProtected(expired,{status:'running',lastHeartbeatAt:at(1)},now),true);
  assert.equal(isStorybookLeaseProtected(expired,{status:'running',lastHeartbeatAt:at(3)},now),false);
  assert.equal(isStorybookLeaseProtected({leaseExpiresAt:at(-10)},{status:'aiComplete'},now),false);
  const h=harness();h.rows.set(h.leasePath,expired);
  h.rows.set(h.jobPath,{status:'running_continue',lastHeartbeatAt:at(30)});
  const active=await h.db.collection('users').doc('user').collection('aiUsage').doc('storybook_active').get();
  const args={transaction:{get:ref=>ref.get()},db:h.db,active,userId:'user',jobId:'new',now};
  assert.equal(await hasProtectedStorybookLease(args),true);
  h.rows.set(h.jobPath,{status:'complete'});
  assert.equal(await hasProtectedStorybookLease(args),false);
});
