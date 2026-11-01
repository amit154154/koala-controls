'use strict';
const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
let tick=0;const played=[];
const emitted=[],buttons=[9,10,11,12].map(n=>({dataset:{key:String(n)},disabled:false,setPointerCapture(){}}));
const root={querySelector(){return null;},querySelectorAll(s){return s==='[data-key]'?buttons:[];}};
const document={hidden:false,getElementById(){return root;},querySelectorAll(){return[];},addEventListener(){},createElement(){return{play(){played.push(this.src);return Promise.resolve();}};},body:{append(){}}};
const context={window:{},document,localStorage:{getItem(){return null;}},fetch:()=>Promise.resolve({ok:true,arrayBuffer:()=>Promise.resolve(new ArrayBuffer(0))}),performance:{now(){tick+=100;return tick;}},Promise,Map,Set,Math,setTimeout,clearTimeout};
vm.runInNewContext(fs.readFileSync(process.argv[2]+'/adventure.js','utf8'),context);

played.length=0;for(let i=0;i<24;i++)context.window.KoalaAdventure.sound.tap(true);
const paths=played.map(p=>p.split('/').at(-1));const allowed=['004','005','006','007','008','009','010','014'].map(n=>'Maplestory-'+n+'.wav');
assert.equal(paths.length,24);for(let bag=0;bag<3;bag++)assert.deepEqual(paths.slice(bag*8,bag*8+8).sort(),allowed.slice().sort());
for(let i=1;i<paths.length;i++)assert.notEqual(paths[i],paths[i-1]);assert.ok(paths.every(p=>!['Maplestory-001.wav','Maplestory-011.wav'].includes(p)));
played.length=0;context.window.KoalaAdventure.sound.tap();assert.equal(played[0],'/sounds/Maplestory-004.wav');
context.window.KoalaAdventure.sound.setEnabled(false);context.window.KoalaAdventure.sound.tap(true);assert.equal(played.length,1);
console.log('Phone audio checks passed: three complete eight-sound bags, no immediate repeats, reserved files excluded, fixed UI tap and mute.');
context.window.KoalaAdventure.sound.setEnabled(true);

context.window.KoalaAdventure.wireCorners({ready:()=>true,runKey:n=>emitted.push(['key',n]),runCorner:c=>emitted.push(['corner',c]),help:n=>emitted.push(['help',n])});
function b(n){return buttons.find(x=>+x.dataset.key===n);}
function down(n){b(n).onpointerdown({pointerId:n,clientX:0,clientY:0});}
function up(n){b(n).onpointerup({pointerId:n,clientX:0,clientY:0});}
for(const [a,b,c] of [[10,11,'topLeft'],[12,11,'topRight'],[10,9,'bottomLeft'],[12,9,'bottomRight']])for(const reverse of [false,true]){
 emitted.length=0;const pair=reverse?[b,a]:[a,b];down(pair[0]);down(pair[1]);up(pair[0]);up(pair[1]);assert.deepEqual(emitted,[['corner',c]]);
}
for(const n of [9,10,11,12]){emitted.length=0;down(n);assert.deepEqual(emitted,[]);up(n);assert.deepEqual(emitted,[['key',n]]);}
emitted.length=0;down(10);down(11);down(9);up(10);up(11);up(9);assert.deepEqual(emitted,[['corner','topLeft']]);
emitted.length=0;down(9);b(9).onpointercancel();up(9);assert.deepEqual(emitted,[]);
console.log('14 phone chord scenarios passed: all corners in both orders, isolated keys, third-key suppression and canceled touch.');
