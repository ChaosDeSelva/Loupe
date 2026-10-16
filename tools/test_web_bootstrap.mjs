import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const html=readFileSync(new URL('../examples/afterimage/tools/web/index.html',import.meta.url),'utf8');
const code=html.slice(html.indexOf('function deferredRavensight('),html.indexOf('function watchGameReady('));
function harness(){
 const counts={construct:0,init:0,track:0};
 const create=vm.runInNewContext(code+';deferredRavensight', {console});
 const client=create(()=>{counts.construct++;return {
  initialized:false,setEnabled(){},init(){counts.init++;return Promise.resolve();},
  track(){counts.track++;},flush(){return Promise.resolve();},_flushOnHidden(){return false;}
 };});
 return {client,counts};
}
test('no construction, identity or session before authoritative readiness',()=>{
 const {client,counts}=harness();client.setEnabled(true);client.init();client.track('early');
 assert.deepEqual(counts,{construct:0,init:0,track:0});
 client.ready(true);client.init();client.ready(true);client.track('session_started');
 assert.deepEqual(counts,{construct:1,init:1,track:1});
});
test('saved opt-out is final even if an enabled line arrives later',()=>{
 const {client,counts}=harness();client.setEnabled(false);client.ready(false);
 client.setEnabled(true);client.ready(true);client.init();client.track('late');
 assert.deepEqual(counts,{construct:0,init:0,track:0});
});
test('opt-out after startup suppresses further events',()=>{
 const {client,counts}=harness();client.ready(true);client.setEnabled(false);
 client.track('late');client.setEnabled(true);client.track('later');
 assert.equal(counts.track,0);
});
