const assert = require('node:assert/strict');
const test = require('node:test');
const { buildFastOnboardingIllustrationPrompt: build } = require('./onboardingIllustrationPolicy');
const base = {profileName:'Alex',storyText:'At nine I collected shells with my sister.',hasHeadshot:true,hasStyleReference:true};
test('keeps source memory intact without injecting a scene-specific age or relative',()=>{
 const prompt=build(base);
 assert.ok(prompt.endsWith(base.storyText));
 assert.ok(!prompt.includes('EIGHT-YEAR-OLD'));
 assert.ok(!prompt.includes('His father'));
 assert.match(prompt,/explicit adulthood overrides childhood/);
 assert.match(prompt,/never a biographical fact/);
});
test('separates current portrait identity from scene age and all other characters',()=>{
 const prompt=build(base);
 assert.match(prompt,/Reference 1 is STYLE ONLY/);
 assert.match(prompt,/Reference 2 is Alex's current portrait, IDENTITY ONLY/);
 assert.match(prompt,/portrait becomes that CHILD, never the adult beside them/);
 assert.match(prompt,/ages must follow the memory, not the portrait/);
 assert.match(prompt,/familial resemblance is fine/);
 assert.match(prompt,/remove wrinkles, gray hair, facial hair and adult proportions/);
});
test('keeps helper perspective and reference numbering correct',()=>{
 const prompt=build({...base,storytellerRole:'helper',hasStyleReference:false});
 assert.match(prompt,/Reference 1 is Alex's current portrait/);
 assert.match(prompt,/First-person I\/my refers to the helper/);
 assert.match(prompt,/unless explicitly quoting Alex/);
});
test('supports missing photo and never introduces a reference attachment',()=>{
 const prompt=build({...base,hasHeadshot:false,hasStyleReference:false});
 assert.match(prompt,/No identity portrait is attached/);
 assert.ok(!prompt.includes('Reference 1'));
});
test('rejects missing subject, missing memory and unknown role',()=>{
 for(const input of [{...base,profileName:''},{...base,storyText:''},{...base,storytellerRole:'unknown'}]) assert.throws(()=>build(input));
});

test('requires simple cartoon styling and a single scene',()=>{
 const prompt=build(base);
 assert.match(prompt,/ONE SINGLE full-bleed/);
 assert.match(prompt,/tiny dot eyes/);
 assert.match(prompt,/No fine hatching/);
});
test('descriptor mode binds broad appearance only to named subject',()=>{
 const prompt=build({...base,hasHeadshot:false,subjectAppearance:'warm brown skin and a round face'});
 assert.match(prompt,/guidance for Alex alone: warm brown skin and a round face/);
 assert.match(prompt,/never detailed anatomical rendering/);
});
