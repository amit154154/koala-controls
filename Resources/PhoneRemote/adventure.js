'use strict';
(() => {
 const root=document.getElementById('koala-remote-concept'),q=s=>root.querySelector(s),esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const corners=[['topLeft','↖','Top left','10 + 11','win_tl'],['topRight','↗','Top right','12 + 11','win_tr'],['bottomLeft','↙','Bottom left','10 + 9','win_bl'],['bottomRight','↘','Bottom right','12 + 9','win_br']];
 const ids=['grove_connect','grove_viz','grove_media','grove_write','grove_code','grove_build','grove_setup','grove_claude','win_min','win_left','win_max','win_right'];
 const titles=['Connect','Koala Viz','Media','Notes & chat','Code focus','Build & browse','Set up all','Claude desk','Minimize','Left half','Fill screen','Right half'];
 const flavors=['Portal passport','Stonks, but make it koala','Courtside koala','Paper-plane postmaster','One more line, one more leaf','Slime eviction specialist','Three-screen orchestra','Two brains, zero spare branches','Professional hide-and-seek','Window parkour','Window parkour','Window parkour'];
 const accents=['Original adventure','Leaf trail','Star burst','Golden orbit','Cosmic grove'];
 let enabled=localStorage.getItem('tapSounds')!=='false',context,lastSound=-Infinity,bag=[],lastMovement,stats=null,levelPlaying=false;
 const buffers=new Map(),encoded=new Map(),decoding=new Map(),seen=new Set(),levelQueue=[];
 const movement=['004','005','006','007','008','009','010','014'];
 const allowed=[...movement,'001','011'];
 // Fetch the exact bundled files ahead of the first tap. Decode after Safari has a user gesture.
 const requests=allowed.map(name=>fetch('/sounds/Maplestory-'+name+'.wav').then(r=>{if(!r.ok)throw Error();return r.arrayBuffer();}).then(b=>encoded.set(name,b)).catch(()=>{}));
 const pool=Array.from({length:4},(_,i)=>{const a=document.createElement('audio');a.id='koala-tap-audio-'+i;a.src='/sounds/Maplestory-004.wav';a.preload='auto';a.volume=.35;a.hidden=true;document.body.append(a);return a;});
 let poolIndex=0;
 function unlock(){
  const Audio=window.AudioContext||window.webkitAudioContext;
  if(!context&&Audio){try{context=new Audio();}catch{}}
  if(context){context.resume().catch(()=>{});Promise.all(requests).then(()=>allowed.forEach(decode));}
 }
 function decode(name){
  if(buffers.has(name))return Promise.resolve(buffers.get(name));
  if(decoding.has(name))return decoding.get(name);
  const raw=encoded.get(name);if(!context||!raw)return Promise.resolve(null);
  const promise=context.decodeAudioData(raw.slice(0)).then(b=>{buffers.set(name,b);return b;}).catch(()=>null);
  decoding.set(name,promise);return promise;
 }
 function emit(name){
  if(!enabled||document.hidden)return;
  if(context){Promise.all(requests).then(()=>decode(name)).then(b=>{if(!b||!enabled||document.hidden||context.state!=='running')return;const s=context.createBufferSource(),g=context.createGain();s.buffer=b;g.gain.value=.35;s.connect(g);g.connect(context.destination);s.start();});}
  else {const a=pool[poolIndex++%pool.length];a.src='/sounds/Maplestory-'+name+'.wav';try{a.currentTime=0;}catch{}a.play().catch(()=>{});}
 }
 function nextMovement(){if(!bag.length){bag=movement.slice().sort(()=>Math.random()-.5);if(bag.at(-1)===lastMovement)[bag[0],bag[bag.length-1]]=[bag.at(-1),bag[0]];}return lastMovement=bag.pop();}
 function tap(moving=false,force=false){if((!enabled&&!force)||document.hidden)return;unlock();const now=performance.now();if(now-lastSound<35)return;lastSound=now;const was=enabled;if(force)enabled=true;emit(moving?nextMovement():'004');enabled=was;}
 function movementTarget(target){const button=target.closest?.('[data-key],[data-corner],[data-command]');if(!button)return false;return button.hasAttribute('data-corner')||[4,5,6,7,9,10,11,12].includes(Number(button.dataset.key))||/Space/.test(button.dataset.command||'');}
 document.addEventListener('click',e=>{if(!e.isTrusted||e.target.closest?.('#kr-trackpad,label[for]'))return;if(e.detail>0&&e.target.closest?.('[data-chord-key]'))return;if(e.target.id==='kr-sound'){tap(false,e.target.checked);return;}tap(movementTarget(e.target));},true);
 document.addEventListener('input',e=>{if(e.isTrusted&&e.target.matches?.('textarea,input:not([type="range"]):not([type="checkbox"])'))tap();});
 document.addEventListener('change',e=>{if(e.isTrusted&&e.target.matches?.('select'))tap();});
 function update(data){stats=data;if(!data)return;const p=q('#kr-passport');if(!p)return;
  const core=ids.concat(corners.map(c=>c[4]));const all=core.concat((data.skills||[]).map(s=>s.id).filter(id=>!core.includes(id)));const byID=new Map((data.skills||[]).map(s=>[s.id,s]));
  p.innerHTML='<div class="kr-passport-head"><img src="/art/companion.jpg" alt=""/><div><h2>Grove Adventurer</h2><strong>Level '+esc(data.level)+'</strong><p>'+esc(data.title)+'</p></div></div><progress aria-label="Player XP" value="'+Math.max(0,data.xp-data.floor)+'" max="'+Math.max(1,data.next-data.floor)+'"></progress><div class="kr-xp-line"><span>'+esc(data.xp)+' XP · '+esc(data.clicks)+' clicks</span><span>'+(data.next-data.xp)+' to level '+(data.level+1)+'</span></div>';
  q('#kr-mastery').innerHTML=all.map((id,i)=>{const s=byID.get(id)||{uses:0,level:1,tier:0,next:10,floor:0};const extras={tab_prev:'Previous tab',tab_next:'Next tab',space_prev:'Previous Space',space_next:'Next Space',volume:'Mac volume',media_arrange:'Arrange media',media_focus:'Focus media',grove_guide:'Keypad guide'};const name=i<12?titles[i]:corners.find(c=>c[4]===id)?.[2]||extras[id]||id.replaceAll('_',' ');return '<div class="kr-mastery-row"><div><strong>'+esc(name)+'</strong><span>Lv. '+s.level+'</span></div><small>'+esc(s.flavor||(i<12?flavors[i]:'Window parkour'))+'</small><progress aria-label="'+esc(name)+' mastery" value="'+(s.uses-s.floor)+'" max="'+Math.max(1,s.next-s.floor)+'"></progress><div class="kr-xp-line"><span>'+s.uses+' uses</span><span>'+(s.tier?accents[s.tier]:'Leaf trail at level 2')+'</span></div></div>';}).join('');
  q('#kr-activity').innerHTML=(data.recent||[]).map(c=>'<li><strong>'+esc(c.name)+'</strong><time>'+esc(new Date(c.timestamp).toLocaleString(undefined,{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit',second:'2-digit'}))+'</time><small>'+esc(c.source)+' · Pad '+(c.keyboardConnected?'connected':'disconnected')+' · '+esc(c.result)+'</small></li>').join('')||'<li>Your first shortcut starts the adventure. The koala packed one leaf.</li>';
 }
 function tier(id){return (stats?.skills||[]).find(s=>s.id===id)?.tier||0;}
 function earned(list){for(const n of list||[]){if(seen.has(n.id))continue;seen.add(n.id);levelQueue.push(n);}if(!levelPlaying)nextLevel();}
 function nextLevel(){
  if(!levelQueue.length){levelPlaying=false;return;}levelPlaying=true;
  const n=levelQueue.shift(),el=q('#kr-level-up');
  emit(n.scope==='player'?'011':'001');
  el.innerHTML='<img src="/art/companion.jpg" alt=""/><div><small>'+(n.scope==='player'?'The grove has promoted you!':'New trick, same tiny paws.')+'</small><strong>Level '+esc(n.level)+'</strong><span>'+esc(n.name)+'</span><p>'+esc(n.unlocked)+'</p></div>';
  el.dataset.scope=n.scope;el.hidden=false;el.classList.remove('is-celebrating');void el.offsetWidth;el.classList.add('is-celebrating');
  if(localStorage.getItem('reduced')==='true')el.classList.add('is-reduced');else el.classList.remove('is-reduced');
  setTimeout(()=>{el.hidden=true;},1700);setTimeout(nextLevel,n.scope==='player'?4700:2100);
 }
 function wireCorners(options){
  for(const container of root.querySelectorAll('.kr-corner-grid'))container.innerHTML=corners.map(([id,glyph,title,pair])=>'<button type="button" class="kr-corner" data-corner="'+id+'" aria-label="'+title+' corner"><b aria-hidden="true">'+glyph+'</b><span>'+title+'</span><small>'+pair+'</small></button>').join('');
  root.querySelectorAll('[data-corner]').forEach(b=>b.onclick=()=>options.runCorner(b.dataset.corner));
  const held=new Map(),consumed=new Set();
  const cancelTimers=()=>held.forEach(h=>clearTimeout(h.timer));
  function reset(){cancelTimers();held.clear();consumed.clear();}
  for(const b of root.querySelectorAll('[data-key]')){
   const n=Number(b.dataset.key);if(![9,10,11,12].includes(n))continue;b.dataset.chordKey='true';
   b.onpointerdown=e=>{
    if(!options.ready()||b.disabled)return;b.setPointerCapture(e.pointerId);
    if(held.has(n))return;
    const h={pointer:e.pointerId,x:e.clientX,y:e.clientY,timer:null};held.set(n,h);
    if(consumed.size){consumed.add(n);return;}
    const pairs=[[[10,11],'topLeft'],[[12,11],'topRight'],[[10,9],'bottomLeft'],[[12,9],'bottomRight']];
    for(const [pair,c]of pairs)if(pair.every(k=>held.has(k))){cancelTimers();held.forEach((_,k)=>consumed.add(k));tap(true);options.runCorner(c);return;}
    // Combo keys stay available while held. The ? mode supplies their help.
   };
   b.onpointermove=e=>{const h=held.get(n);if(h&&Math.hypot(e.clientX-h.x,e.clientY-h.y)>16){cancelTimers();held.forEach((_,k)=>consumed.add(k));}};
   b.onpointerup=e=>{const h=held.get(n);if(!h||h.pointer!==e.pointerId)return;clearTimeout(h.timer);held.delete(n);const run=!consumed.has(n);if(!held.size)consumed.clear();if(run){tap(true);options.runKey(n);}};
   b.onpointercancel=()=>{cancelTimers();held.forEach((_,k)=>consumed.add(k));held.delete(n);if(!held.size)consumed.clear();};
   b.onclick=e=>{if(e.detail===0)options.runKey(n);};
  }
  document.addEventListener('visibilitychange',()=>{if(document.hidden)reset();});
 }
 window.KoalaAdventure={corners,ids,update,tier,earned,wireCorners,sound:{tap,setEnabled:value=>{enabled=value;}}};
})();
