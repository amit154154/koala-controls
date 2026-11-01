'use strict';
(() => {
 const root=document.getElementById('koala-remote-concept'),q=s=>root.querySelector(s),qa=s=>[...root.querySelectorAll(s)],keys=window.KoalaKeys;
 const services=[['youtubeMusic','YouTube Music'],['spotify','Spotify'],['youtube','YouTube'],['gdn','GDN Play'],['netflix','Netflix'],['hbo','HBO Max'],['nba','NBA League Pass'],['appleTV','Apple TV']];
 const png=new Set(['obsidian','slack','vscode','zed','chrome','youtubeMusic','spotify','youtube','gdn','appleTV']);
 const art=name=>'/art/'+name+(png.has(name)?'.png':'.jpg');
 const icons={'chevron-down':'⌄','chevron-left':'‹','chevron-right':'›','circle-help':'?','laptop':'▱','tablet':'▯','monitor':'▱','volume-2':'♪','wifi-off':'○','check':'✓','grid-3x3':'▦','play':'▶','mouse-pointer-2':'↗','x':'×'};
 const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const state={view:'pad',live:null,connected:false,offset:0,target:localStorage.getItem('mediaTarget')||'auto',workspace:localStorage.getItem('workspaceTarget')||'auto',selected:'youtube',help:false,feedback:localStorage.getItem('feedback')||'phone',sounds:localStorage.getItem('tapSounds')!=='false',awake:localStorage.getItem('awake')!=='false',reduced:localStorage.getItem('reduced')==='true'};
 let pollTimer,pairTimer,wakeLock,refreshing=false,pairing=false,returnFocus,pressTimer,held=false,reactionTimer,volumeTimer,typingFocus=null;
 let sinceRare=3,mobs=[],gestures=new Map(),pointerDelta={dx:0,dy:0,kind:'pointer'},pointerSending=false,scrollGesture=false,gestureMoved=false,gestureStarted=0,lastCenter;
 const adventure=window.KoalaAdventure;
 const outstanding=new Map();
 try{for(const x of JSON.parse(sessionStorage.getItem('koalaPending')||'[]'))if(x&&typeof x.id==='string')outstanding.set(x.id,x);}catch{}
 function remember(){sessionStorage.setItem('koalaPending',JSON.stringify([...outstanding.values()].slice(-12)));}
 function status(text){q('#kr-status span').textContent=text||'Ready when you are.';}
 function hydrate(){qa('[data-art]').forEach(img=>img.src=art(img.dataset.art));qa('[data-lucide]').forEach(el=>{el.textContent=icons[el.dataset.lucide]||'•';el.setAttribute('aria-hidden','true');});}
 const television=window.KoalaTV.create({root,command,showView,sheet,closeSheet,status});
 function controls(){qa('.kr-key,.kr-corner,.kr-service,[data-command],#kr-send,#kr-trackpad,#kr-tile,#kr-focus,#kr-mute,#kr-focus-app').forEach(el=>el.disabled=!state.connected||!!state.live?.busy||!!state.live?.layoutBusy||!state.live?.accessibility);q('#kr-volume-range').disabled=!state.connected||state.live?.volume==null;}
 function connected(ok){television.update(state.live,ok);if(ok&&!state.connected)status('Ready when you are.');state.connected=ok;q('#kr-offline').hidden=ok;controls();q('#kr-connection-label').textContent=ok?(state.live?.macName||'Your Mac'):'Mac unavailable';q('#kr-connected').textContent=ok?'Connected':'Unavailable';if(!ok){gestures.clear();pointerDelta={dx:0,dy:0,kind:'pointer'};}}
 async function api(path,body,signal){
  const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),12000);let response;try{response=await fetch(path,{method:body===undefined?'GET':'POST',headers:{'X-Koala-Client':'1',...(body===undefined?{}:{'Content-Type':'application/json'})},credentials:'same-origin',cache:'no-store',body:body===undefined?undefined:JSON.stringify(body),signal:signal||controller.signal});}finally{clearTimeout(timeout);}
  const data=await response.json();if(!response.ok){const e=new Error(data.error||'Your Mac could not complete that request.');e.http=response.status;throw e;}return data;
 }
 function pairedUI(show){document.getElementById('pair-screen').hidden=show;root.hidden=!show;}
 function targetDisplay(media){const value=media?state.target:state.workspace;const list=state.live?.displays||[];if(value==='auto')return (media?list.find(x=>x.ipad):null)||list.find(x=>x.builtin)||list[0];return list.find(x=>x.id===value);}
 function renderMedia(){
  const display=targetDisplay(true);q('#kr-media-target-name').textContent=display?display.name+(state.target==='auto'?' · automatic':''):'Choose a connected display';
  q('#kr-open-title').textContent=display?'On your '+display.name:'Media windows';
  const entries=state.live?.mediaDisplay===display?.id?(state.live?.media||[]):[];
  q('#kr-open-count').textContent=entries.length+' '+(entries.length===1?'window':'windows');
  q('#kr-media-preview').innerHTML=entries.length?entries.map(x=>'<button type="button" class="cursor-interaction" data-open="'+escape(x.service)+'" aria-pressed="'+(state.selected===x.service)+'">'+(png.has(x.service)?'<img src="'+art(x.service)+'" alt="" />':'')+escape(x.name)+'</button>').join(''):'<span class="kr-caption">Open a service above to start.</span>';
  q('#kr-media-preview').style.gridTemplateColumns=entries.length>4?'repeat(3,1fr)':'repeat(2,1fr)';
  qa('[data-open]').forEach(b=>b.onclick=()=>{state.selected=b.dataset.open;renderMedia();});
  qa('[data-service]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.service===state.selected)));
  q('#kr-media-rule').textContent=display?.ipad?'A new service joins the layout. Existing ones are reused.':'Media fills this display. Sharing is automatic on iPad.';
  q('#kr-tile').disabled=!state.connected||!entries.length||state.live?.busy;q('#kr-focus').disabled=!state.connected||!entries.some(x=>x.service===state.selected)||state.live?.busy;
 }
 function render(){
  if(!state.live)return;
  const l=state.live,d=l.displays||[],ipad=d.find(x=>x.ipad);
  q('#kr-setup-label').textContent=l.mobile?'Home setup':'Desk setup';q('#kr-context-displays').textContent=d.map(x=>x.name).join(' + ');
  q('#kr-workspace-rule').textContent=l.mobile?'Workspaces open in MacBook Spaces':'Workspaces open on '+(targetDisplay(false)?.name||'a missing display');q('#kr-workspace-target').hidden=l.mobile;
  q('#kr-active-app').textContent=l.frontApp;q('#kr-focus-app img').src=art(({'com.google.Chrome':'chrome','com.microsoft.VSCode':'vscode','md.obsidian':'obsidian','dev.zed.Zed':'zed','com.tinyspeck.slackmacgap':'slack'})[l.frontBundle]||'companion');
  q('.kr-paired strong').textContent=l.macName;q('#kr-paired-label').textContent=l.peer+' · paired locally';q('#kr-ipad').textContent=ipad?'Connected':'Not connected';q('#kr-desk').textContent=l.mobile?'Home · mobile':'Desk · external monitors';
  q('#kr-reactions').value=state.feedback;q('#kr-sound').checked=state.sounds;q('#kr-awake').checked=state.awake;q('#kr-reduced').checked=state.reduced;
  if(document.activeElement!==q('#kr-volume-range')){const v=Math.round((l.volume||0)*100);q('#kr-volume-range').value=v;q('#kr-volume-value').textContent=l.volume==null?'—':v+'%';}
  connected(true);renderMedia();adventure.update(l.adventure);
  if(!l.accessibility)status('Enable Mini Keyboard’s Accessibility permission on your Mac.');
 }
 async function refresh(){
  if(refreshing||document.hidden||pairing)return;refreshing=true;
  try{const l=await api('/api/state');state.live=l;state.offset=l.serverTime-Date.now()/1000;pairedUI(true);render();
   if(state.view==='media'){try{Object.assign(state.live,await api('/api/media-state',{display:state.target}));renderMedia();}catch(e){status(e.message);}}
   for(const [id,info]of [...outstanding])await recover(id,info);
  }catch(e){connected(false);if(e.http===401){pairedUI(false);document.getElementById('pair-status').textContent=e.message;}else{status('Mac unavailable. No taps will be queued.');if(root.hidden)document.getElementById('pair-status').textContent='Keep Mini Keyboard running and connect both devices to the same Wi-Fi.';}}
  finally{refreshing=false;clearTimeout(pollTimer);pollTimer=setTimeout(refresh,1500);}
 }
 async function recover(id,info){try{const result=await api('/api/job/'+id);if(result.status!=='running'){outstanding.delete(id);remember();complete(result,info);}}catch(e){if(e.http===404){outstanding.delete(id);remember();status('That action’s result is unavailable. It has not been retried.');}}}
 function complete(result,info){
  if(result.tv&&state.live){state.live.tv=result.tv;television.update(state.live,state.connected);}
  adventure.earned(result.earned);
  if(result.message)status(result.message);
  if(result.status==='failed'){
   if(info.service==='spotify'&&/fit|minimum window/i.test(result.message)){sheet('Spotify needs more room','<p class="kr-help-copy">'+escape(result.message)+'</p><button type="button" class="kr-choice" id="spotify-browser">Use Spotify web player</button><button type="button" class="kr-choice" id="spotify-mac">Open Spotify on MacBook</button>');q('#spotify-browser').onclick=()=>{closeSheet();command('media',{service:'spotify',display:state.target,browser:true},{n:3,service:'spotify'});};q('#spotify-mac').onclick=()=>{closeSheet();const mac=state.live.displays.find(d=>d.builtin);if(mac)command('media',{service:'spotify',display:mac.id},{n:3,service:'spotify'});};}
  }else if(info.n||info.corner)reaction(info.n,info.corner);
  if(result.showMedia){state.target='auto';localStorage.setItem('mediaTarget','auto');showView('media');}
 }
 async function command(kind,args={},info={}){
  if(!state.connected){status('Reconnect first. No actions are queued.');return;}
  const id=crypto.randomUUID();const body={id,kind,timestamp:Date.now()/1000+state.offset,focus:state.live.focus,feedback:state.feedback,...args};
  const fast=['pointer','scroll','click','volume','special','text','focusApp','corner'].includes(kind);
  if(!fast){outstanding.set(id,{id,...info});remember();state.live.busy=true;controls();status('Working on your Mac…');}
  try{const result=await api('/api/command',body);if(result.status!=='running'){outstanding.delete(id);remember();complete(result,info);}if(kind==='text'&&result.status==='completed'){q('#kr-type').value='';typingFocus=null;}if(!fast)await refresh();return result;}
  catch(e){if(e.http){outstanding.delete(id);remember();status(e.message);if(state.live)state.live.busy=false;controls();}else{if(!['pointer','scroll'].includes(kind)){outstanding.set(id,{id,...info});remember();}connected(false);status('Connection lost. The action will not be sent again.');}return null;}
 }
 function showView(name){state.view=name;qa('.kr-pane').forEach(p=>p.hidden=p.id!=='kr-'+name);qa('.kr-nav button').forEach(b=>{b.classList.toggle('is-current',b.dataset.view===name);if(b.dataset.view===name)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');});if(name==='media')refresh();window.scrollTo({top:0,behavior:'instant'});}
 function sheet(title,html){returnFocus=document.activeElement;q('#kr-sheet-title').textContent=title;q('#kr-sheet-body').innerHTML=html;q('#kr-sheet-backdrop').hidden=false;for(const el of [q('.kr-header'),q('.kr-content'),q('.kr-nav')])el.inert=true;hydrate();q('#kr-sheet-close').focus();}
 function closeSheet(){q('#kr-sheet-backdrop').hidden=true;for(const el of [q('.kr-header'),q('.kr-content'),q('.kr-nav')])el.inert=false;returnFocus?.focus();}
 function helpKey(key){sheet('Key '+key.n+' · '+key.title,'<img class="kr-help-art" src="'+art(key.id)+'" alt="" /><p class="kr-help-copy">'+escape(key.detail)+'</p><span class="kr-hotkey">'+escape(key.hotkey)+'</span>');}
 function chooseTarget(media){const list=state.live?.displays||[],current=media?state.target:state.workspace;
  sheet(media?'Open media on':'Workspace display',[{id:'auto',name:'Automatic',description:media?'iPad when connected; otherwise MacBook':'MacBook'},...list].map(d=>'<button type="button" class="kr-choice" data-target="'+escape(d.id)+'"><span>'+escape(d.name)+(d.description?'<small>'+escape(d.description)+'</small>':'')+'</span>'+(current===d.id?'✓':'')+'</button>').join(''));
  qa('[data-target]').forEach(b=>b.onclick=()=>{if(media){state.target=b.dataset.target;localStorage.setItem('mediaTarget',state.target);}else{state.workspace=b.dataset.target;localStorage.setItem('workspaceTarget',state.workspace);}closeSheet();render();refresh();});
 }
 const names=['connect','viz','basketball','notes','focus','battle','setup','duo','minimize','left','fill','right'];
 adventure.sound.setEnabled(state.sounds);
 function playTapSound(){adventure.sound.tap();}
 function reaction(n,corner){
  if(state.feedback!=='phone')return;
  if(state.reduced||matchMedia('(prefers-reduced-motion: reduce)').matches)return;
  let name=corner||names[n-1]||'hop',rare=sinceRare>=3&&Math.random()<.08;sinceRare=rare?0:sinceRare+1;
  if(name==='battle'&&!rare){if(!mobs.length)mobs=['greenSnail','blueSnail','redSnail','slime','orangeMushroom','pointyMushroom','stump','pig','purpleMob'].sort(()=>Math.random()-.5);name='mob-'+mobs.pop();}else if(rare)name+='-rare';else if(name==='basketball'&&Math.random()<.25)name+='-miss';
  q('#kr-reaction').dataset.action=corner||names[n-1]||'hop';q('#kr-reaction').dataset.tier=String(adventure.tier(corner?adventure.corners.find(c=>c[0]===corner)[4]:adventure.ids[n-1]));
  const img=q('#kr-reaction img');img.src='/reactions/'+name+'.webp';q('#kr-reaction').classList.add('is-playing');clearTimeout(reactionTimer);reactionTimer=setTimeout(()=>q('#kr-reaction').classList.remove('is-playing'),corner||n>=10?380:1300);
 }
 function draw(){
  q('#kr-key-grid').innerHTML=keys.map(k=>'<button type="button" class="kr-key" data-key="'+k.n+'" aria-label="Key '+k.n+': '+escape(k.title)+'"><img src="'+art(k.id)+'" alt="" /><span class="kr-key-number">'+k.n+'</span>'+(k.apps?'<span class="kr-key-apps">'+k.apps.map(a=>'<img src="'+art(a)+'" alt="'+a+'" />').join('')+'</span>':'')+'<span class="kr-key-title">'+escape(k.title)+'</span></button>').join('');
  q('#kr-media-grid').innerHTML=services.map(([id,name])=>'<button type="button" class="kr-service" data-service="'+id+'" aria-pressed="false">'+(png.has(id)?'<img src="'+art(id)+'" alt="" />':'<span class="kr-service-symbol">'+({netflix:'N',hbo:'HBO',nba:'🏀'})[id]+'</span>')+'<span>'+name+'</span></button>').join('');hydrate();
 }
 function wire(){
  qa('[data-view]').forEach(b=>b.onclick=()=>showView(b.dataset.view));
  qa('[data-key]').forEach(b=>{b.onclick=()=>{if(held){held=false;return;}const n=Number(b.dataset.key);if(state.help){helpKey(keys[n-1]);return;}if(n===3){command('key',{key:3,display:state.workspace});showView('media');return;}command('key',{key:n,display:state.workspace},{n});};b.onpointerdown=()=>{held=false;pressTimer=setTimeout(()=>{held=true;helpKey(keys[Number(b.dataset.key)-1]);},550);};for(const event of ['pointerup','pointercancel','pointerleave'])b.addEventListener(event,()=>clearTimeout(pressTimer));b.oncontextmenu=e=>e.preventDefault();});
  qa('[data-service]').forEach(b=>b.onclick=()=>{state.selected=b.dataset.service;command('media',{service:state.selected,display:state.target},{n:3,service:state.selected});});
  q('#kr-help').onclick=()=>{state.help=!state.help;showView('pad');q('#kr-help').setAttribute('aria-pressed',String(state.help));status(state.help?'Help mode: tap a key to see its shortcut.':'Help closed. Tap a key to run it.');};
  q('#kr-media-target').onclick=()=>chooseTarget(true);q('#kr-workspace-target').onclick=()=>chooseTarget(false);q('#kr-sheet-close').onclick=closeSheet;q('#kr-sheet-backdrop').onclick=e=>{if(e.target===q('#kr-sheet-backdrop'))closeSheet();};
  root.addEventListener('keydown',e=>{if(e.key==='Escape')closeSheet();if(e.key==='Tab'&&!q('#kr-sheet-backdrop').hidden){const list=[...q('.kr-sheet').querySelectorAll('button,input,select,textarea')].filter(e=>!e.disabled);if(e.shiftKey&&document.activeElement===list[0]){e.preventDefault();list.at(-1).focus();}else if(!e.shiftKey&&document.activeElement===list.at(-1)){e.preventDefault();list[0].focus();}}});
  const commands={'Previous tab':'previousTab','Next tab':'nextTab','Escape':'escape','Return':'return','Undo':'undo','Previous Space':'previousSpace','Next Space':'nextSpace'};
  qa('[data-command]').forEach(b=>b.onclick=()=>{const c=b.dataset.command;if(c==='Left click'||c==='Right click')command('click',{button:c==='Left click'?'left':'right'});else command('special',{special:commands[c]});});
  q('#kr-volume-range').oninput=e=>{q('#kr-volume-value').textContent=e.target.value+'%';clearTimeout(volumeTimer);volumeTimer=setTimeout(()=>command('volume',{value:Number(e.target.value)/100}),100);};q('#kr-mute').onclick=()=>command('volume',{value:(state.live.volume||0)>0?0:.35});
  q('#kr-tile').onclick=()=>command('arrangeMedia',{display:state.target});q('#kr-focus').onclick=()=>command('focusMedia',{display:state.target,service:state.selected});
  q('#kr-reactions').onchange=e=>{state.feedback=e.target.value;localStorage.setItem('feedback',state.feedback);};q('#kr-sound').onchange=e=>{state.sounds=e.target.checked;localStorage.setItem('tapSounds',state.sounds);adventure.sound.setEnabled(state.sounds);};q('#kr-reduced').onchange=e=>{state.reduced=e.target.checked;localStorage.setItem('reduced',state.reduced);};q('#kr-awake').onchange=e=>{state.awake=e.target.checked;localStorage.setItem('awake',state.awake);requestWake();};q('#kr-retry').onclick=refresh;
  q('#kr-pairing').textContent='Pairing help';q('#kr-pairing').onclick=()=>sheet('Pairing and access','<p class="kr-help-copy">Open Mini Keyboard → Phone remote on your Mac to pair another phone or revoke access. Add this remote to your Home Screen using Safari’s Share menu.</p>');
  q('#kr-type').onfocus=()=>{if(!q('#kr-type').value)typingFocus=state.live?.focus;};q('#kr-type').oninput=()=>{if(!typingFocus)typingFocus=state.live?.focus;};q('#kr-send').onclick=()=>{const text=q('#kr-type').value;if(!text)return;command('text',{text,focus:typingFocus||state.live.focus});};
  const retarget=document.createElement('button');retarget.type='button';retarget.className='kr-inline-button';retarget.textContent='Use current Mac field';q('.kr-textbox').append(retarget);retarget.onclick=()=>{typingFocus=state.live?.focus;status('Typing target updated to '+state.live.frontApp+'.');};
  q('#kr-focus-app').onclick=()=>{sheet('Focus a running app',(state.live.apps||[]).map(a=>'<button type="button" class="kr-choice" data-app="'+escape(a.id)+'">'+escape(a.name)+'</button>').join(''));qa('[data-app]').forEach(b=>b.onclick=()=>{closeSheet();command('focusApp',{app:b.dataset.app}).then(refresh);});};
  adventure.wireCorners({ready:()=>state.connected&&!state.live?.busy&&!state.live?.layoutBusy,runKey:n=>{if(state.help){helpKey(keys[n-1]);return;}command('key',{key:n,display:state.workspace},{n});},runCorner:corner=>{if(state.help){const c=adventure.corners.find(c=>c[0]===corner);sheet(c[2]+' corner','<p class="kr-help-copy">Move the focused Mac window to this quarter of its current display.</p><span class="kr-hotkey">Pad '+c[3]+'</span>');return;}command('corner',{corner},{corner});},help:n=>helpKey(keys[n-1])});
  const pad=q('#kr-trackpad');pad.onpointerdown=e=>{if(!state.connected||state.live?.busy||!state.live?.accessibility)return;pad.setPointerCapture(e.pointerId);gestures.set(e.pointerId,{x:e.clientX,y:e.clientY});if(gestures.size===1){gestureStarted=performance.now();gestureMoved=false;scrollGesture=false;}if(gestures.size>1)scrollGesture=true;lastCenter=center();};
  pad.onpointermove=e=>{if(!gestures.has(e.pointerId)||!state.connected)return;gestures.set(e.pointerId,{x:e.clientX,y:e.clientY});const c=center();const dx=c.x-lastCenter.x,dy=c.y-lastCenter.y;const kind=scrollGesture?'scroll':'pointer';if(pointerDelta.kind!==kind)pointerDelta={dx:0,dy:0,kind};lastCenter=c;if(Math.abs(dx)+Math.abs(dy)>1)gestureMoved=true;pointerDelta.dx+=dx*(scrollGesture?1:1.7);pointerDelta.dy+=dy*(scrollGesture?1:1.7);flushPointer();};
  pad.onpointerup=e=>{gestures.delete(e.pointerId);if(!gestures.size){if(!gestureMoved&&performance.now()-gestureStarted<300){playTapSound();command('click',{button:scrollGesture?'right':'left'});}scrollGesture=false;}else lastCenter=center();};pad.onpointercancel=e=>{gestures.delete(e.pointerId);pointerDelta={dx:0,dy:0,kind:'pointer'};};pad.oncontextmenu=e=>e.preventDefault();
 }
 function center(){const p=[...gestures.values()];return{x:p.reduce((s,x)=>s+x.x,0)/p.length,y:p.reduce((s,x)=>s+x.y,0)/p.length};}
 async function flushPointer(){if(pointerSending||!state.connected||document.hidden)return;pointerSending=true;while(state.connected&&!document.hidden&&(Math.abs(pointerDelta.dx)+Math.abs(pointerDelta.dy)>.5)){const dx=Math.max(-300,Math.min(300,pointerDelta.dx)),dy=Math.max(-300,Math.min(300,pointerDelta.dy));const kind=pointerDelta.kind;pointerDelta={dx:0,dy:0,kind};await command(kind,{dx,dy});}pointerSending=false;}
 async function requestWake(){try{await wakeLock?.release();wakeLock=null;if(state.awake&&!document.hidden&&navigator.wakeLock)wakeLock=await navigator.wakeLock.request('screen');}catch{}}
 document.getElementById('pair-form').onsubmit=async e=>{e.preventDefault();pairing=true;clearTimeout(pairTimer);const label=document.getElementById('pair-status'),button=document.getElementById('pair-button');button.disabled=true;
  try{const answer=await api('/api/pair',{name:document.getElementById('phone-name').value.trim(),code:document.getElementById('pair-code').value.trim()});label.textContent='Approve this phone on your Mac. Matching code: '+answer.check;const until=Date.now()+120000;const poll=async()=>{try{const result=await api('/api/pair-status',{proof:answer.proof});if(result.status==='paired'){pairing=false;button.disabled=false;document.getElementById('pair-code').value='';refresh();requestWake();}else if(Date.now()<until)pairTimer=setTimeout(poll,1000);else throw new Error('Pairing expired. Generate a new code on your Mac.');}catch(error){if(!error.http&&Date.now()<until){label.textContent='Waiting for your Mac…';pairTimer=setTimeout(poll,1500);}else{pairing=false;button.disabled=false;label.textContent=error.message;}}};poll();
  }catch(error){pairing=false;button.disabled=false;label.textContent=error.message;}
 };
 document.addEventListener('visibilitychange',()=>{if(document.hidden){clearTimeout(pollTimer);connected(false);gestures.clear();pointerDelta={dx:0,dy:0,kind:'pointer'};wakeLock?.release();wakeLock=null;}else{refresh();requestWake();}});window.addEventListener('online',refresh);window.addEventListener('offline',()=>connected(false));
 root.hidden=true;draw();wire();controls();refresh();requestWake();
})();
