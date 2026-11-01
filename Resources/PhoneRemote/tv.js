'use strict';
window.KoalaTV={create({root,command,showView,sheet,closeSheet,status}){
 const q=s=>root.querySelector(s),qa=s=>[...root.querySelectorAll(s)];
 const escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const services=[['youtubeMusic','YouTube Music'],['spotify','Spotify'],['youtube','YouTube'],['gdn','GDN Play'],['netflix','Netflix'],['hbo','HBO Max'],['nba','NBA'],['appleTV','Apple TV']];
 let live=null,connected=false,signature='';
 function send(control,args={}){return command('tv',{control,...args},{tv:true});}
 function wire(){
  q('#kr-tv-fullscreen').onclick=()=>send('fullscreen');
  q('#kr-tv-mac-screen').onclick=()=>send('macScreen',{blank:!live?.tv?.macScreenBlanked});
  q('#kr-tv-auto-connect').onclick=()=>send('automaticTV',{enabled:!live?.tv?.automaticTV});
  q('#kr-tv-av').addEventListener('toggle',()=>{if(q('#kr-tv-av').open&&connected)send('audioRefresh');});
  q('#kr-tv-cc').onclick=()=>send('captions',{enabled:!live?.tv?.captions?.enabled});
  for(const key of ['source','language','size','position','style'])q('#kr-tv-cc-'+key).onchange=e=>send('captionSettings',{[key]:e.target.value});
  q('#kr-tv-audio-output').onchange=e=>send('audioOutput',{output:e.target.value});
  q('#kr-tv-audio-mute').onclick=()=>send('audioMute',{muted:!live?.tv?.audio?.muted});
  q('#kr-tv-audio-volume').oninput=e=>{q('#kr-tv-audio-value').textContent=e.target.value+'%';};
  q('#kr-tv-audio-volume').onchange=e=>send('audioVolume',{value:Number(e.target.value)/100});
  qa('[data-tv]').forEach(b=>b.onclick=()=>send(b.dataset.tv));
  q('#kr-tv-target').onclick=()=>{
   const list=(live?.displays||[]).filter(d=>!d.ipad);
   sheet('TV display','<p class="kr-help-copy">TV mode remembers your choice. Your regular media shortcuts still use the iPad.</p>'+list.map(d=>'<button type="button" class="kr-choice" data-tv-display="'+escape(d.id)+'">'+escape(d.name)+(live?.tv?.display===d.id?' ✓':'')+'</button>').join(''));
   qa('[data-tv-display]').forEach(b=>b.onclick=()=>{closeSheet();send('display',{display:b.dataset.tvDisplay});});
  };
  q('#kr-tv-add-media').onclick=()=>{
   const open=live?.tv?.session||[];
   sheet('Add to your TV',services.map(([id,name])=>'<button type="button" class="kr-choice" data-tv-add="'+id+'"><span>'+escape(name)+'</span><span>'+(open.some(s=>s.service===id)?'Open ✓':'+')+'</span></button>').join(''));
   qa('[data-tv-add]').forEach(b=>b.onclick=()=>{closeSheet();send('media',{service:b.dataset.tvAdd});});
  };
  q('#kr-tv-trackpad').onclick=async()=>{if(live?.tv?.canResume)await send('trackpad');showView('remote');status('Use the trackpad to select a search field, then type below.');};
  q('#kr-tv-services').innerHTML=services.map(([id,name])=>'<button type="button" class="kr-tv-service" data-tv-service="'+id+'">'+(['youtubeMusic','spotify','youtube','gdn','appleTV'].includes(id)?'<img alt="" src="/art/'+id+'.png">':'<b>'+({netflix:'N',hbo:'HBO',nba:'🏀'})[id]+'</b>')+'<span>'+name+'</span></button>').join('');
  qa('[data-tv-service]').forEach(b=>b.onclick=()=>send('media',{service:b.dataset.tvService}));
 }
 function update(state,ok){
  live=state;connected=ok;const tv=state?.tv||{};
  q('#kr-tv-mac-screen').textContent=tv.macScreenBlanked?'Show Mac screen':'Blank Mac screen';q('#kr-tv-mac-screen').disabled=!ok||!tv.canBlankMac;q('#kr-tv-mac-screen').setAttribute('aria-pressed',String(!!tv.macScreenBlanked));
  q('#kr-tv-mac-screen-note').textContent=tv.macScreenBlanked?'Mac screen is black. You can also click it to reveal it.':'The Mac screen returns when TV ends or disconnects.';
  q('#kr-tv-auto-connect').textContent=(tv.automaticTV?'Automatic TV on':'Automatic TV off')+' · '+(tv.automaticTVName||'Your TV');q('#kr-tv-auto-connect').disabled=!ok;
  const audio=tv.audio||{},cc=tv.captions||{},ready=ok&&!state?.busy&&!tv.busy;
  q('#kr-tv-av-status').textContent=cc.enabled?(cc.preparing?'Preparing captions…':'CC on'):(audio.name||'Sound & live text');
  q('#kr-tv-cc').textContent=cc.enabled?'CC on':'CC off';q('#kr-tv-cc').setAttribute('aria-pressed',String(!!cc.enabled));q('#kr-tv-cc').disabled=!ready||!cc.supported;
  q('#kr-tv-cc-status').textContent=cc.status||'Start a TV session to use live captions.';
  q('#kr-tv-cc-status').classList.toggle('kr-tv-av-error',!!cc.error);
  q('#kr-tv-cc-scope').textContent=cc.explanation||'Chrome audio includes other Chrome tabs. Pause other media for clear captions.';
  const languages=cc.languages||[],languageKey=JSON.stringify(languages);
  if(languages.length&&q('#kr-tv-cc-language').dataset.key!==languageKey){q('#kr-tv-cc-language').dataset.key=languageKey;q('#kr-tv-cc-language').innerHTML=languages.map(l=>'<option value="'+escape(l.id)+'">'+escape(l.name)+'</option>').join('');}
  for(const key of ['source','language','size','position','style']){const el=q('#kr-tv-cc-'+key);el.disabled=!ready;if(document.activeElement!==el&&cc[key])el.value=cc[key];}
  const outputs=audio.outputs||[],outKey=JSON.stringify(outputs);
  if(q('#kr-tv-audio-output').dataset.key!==outKey){q('#kr-tv-audio-output').dataset.key=outKey;q('#kr-tv-audio-output').innerHTML=outputs.map(o=>'<option value="'+escape(o.id)+'">'+escape(o.name)+'</option>').join('');}
  q('#kr-tv-audio-output').disabled=!ready||audio.connecting||!outputs.length;if(document.activeElement!==q('#kr-tv-audio-output'))q('#kr-tv-audio-output').value=audio.selected||'';
  q('#kr-tv-audio-mute').textContent=audio.muted?'Unmute':'Mute';q('#kr-tv-audio-mute').disabled=!ready||!audio.canMute;q('#kr-tv-audio-mute').setAttribute('aria-pressed',String(!!audio.muted));
  const volume=q('#kr-tv-audio-volume');volume.disabled=!ready||!audio.canVolume;if(document.activeElement!==volume){volume.value=Math.round((audio.volume||0)*100);q('#kr-tv-audio-value').textContent=audio.canVolume?volume.value+'%':'—';}q('#kr-tv-audio-hardware').hidden=!!audio.canVolume;
  q('#kr-tv-audio-status').textContent=audio.message||'Refresh to find paired AirPods. Open their case or wear them to connect.';q('#kr-tv-audio-status').classList.toggle('kr-tv-av-error',!!audio.error);
  const headphones=audio.headphones||[],headKey=JSON.stringify(headphones);
  if(q('#kr-tv-headphones').dataset.key!==headKey){q('#kr-tv-headphones').dataset.key=headKey;q('#kr-tv-headphones').innerHTML=headphones.length?headphones.map(h=>'<button type="button" class="kr-choice" data-tv-headphones="'+escape(h.id)+'"><span>'+escape(h.name)+'<small>'+(h.connected?'Bluetooth connected':'Paired with this Mac')+'</small></span><span>Use for sound</span></button>').join(''):'<p class="kr-caption">Pair your AirPods in Mac Bluetooth settings first, then Refresh. Open the case or wear them to connect.</p>';qa('[data-tv-headphones]').forEach(b=>b.onclick=()=>send('audioConnect',{headphones:b.dataset.tvHeadphones}));}
  qa('[data-tv-headphones]').forEach(b=>b.disabled=!ready||!!audio.connecting);

  q('#kr-tv-now').textContent=tv.active?(tv.home?'Koala TV home':tv.current):'Your couch is calling.';
  q('#kr-tv-session').textContent=tv.active?'TV session active':'Start TV on your Mac';
  q('#kr-tv-display').textContent=tv.displayName||'Automatic external display';
  q('#kr-tv-message').textContent=tv.message||'Tap Home to start. Choose a service here or navigate on the TV.';
  q('#kr-tv-fullscreen').textContent=tv.fullscreen?'⛶ Exit full screen':'⛶ Full screen';
  q('#kr-tv-fullscreen').setAttribute('aria-pressed',String(!!tv.fullscreen));
  q('#kr-tv-fullscreen').disabled=!ready||!tv.canResume||!state?.accessibility;
  q('#kr-tv-resume').disabled=!ok||!tv.canResume||state?.busy;
  q('#kr-tv-end').disabled=!ok||!tv.active||state?.busy;
  const openItems=tv.openItems||[],openKey=JSON.stringify(openItems);
  if(q('#kr-tv-open').dataset.key!==openKey){q('#kr-tv-open').dataset.key=openKey;
   q('#kr-tv-open').innerHTML=openItems.length?openItems.map(item=>'<button type="button" class="kr-tv-game" data-tv-open="'+escape(item.id)+'"><span class="kr-tv-game-disc">'+(item.game?'◉':'▶')+'</span><span><strong>'+escape(item.title)+'</strong><small>'+escape(item.subtitle)+'</small></span><span>'+(item.game?'Return':'Resume')+'</span></button>').join(''):'<p class="kr-caption">Your open media apps, Chrome media tabs and running RPCS3 session appear here. Tap Refresh after opening one.</p>';
   qa('[data-tv-open]').forEach(b=>b.onclick=()=>send('resumeOpen',{item:b.dataset.tvOpen}));
  }
  q('#kr-tv-open-note').textContent=tv.openScanNote||(tv.scanningOpen?'Looking for your open media and games…':'');
  qa('[data-tv-open]').forEach(b=>b.disabled=!ok||!!state?.busy||!!tv.busy||!state?.accessibility);
  const session=tv.session||[],sessionKey=JSON.stringify(session);
  q('#kr-tv-share').disabled=!ok||session.length<1||!!state?.busy;
  q('#kr-tv-focus').disabled=!ok||session.length<1||!!state?.busy;
  q('#kr-tv-view-mode').textContent=session.length?(tv.sharing?'Sharing the screen':'Focused on '+tv.current):'Open another service to split the TV.';
  if(q('#kr-tv-watching').dataset.key!==sessionKey){q('#kr-tv-watching').dataset.key=sessionKey;
   q('#kr-tv-watching').innerHTML=session.length?session.map(s=>'<div class="kr-tv-watching-row"><button type="button" data-tv-focus="'+escape(s.service)+'" aria-pressed="'+s.focused+'"><strong>'+escape(s.name)+'</strong><small>'+(s.focused?'Controlling':'Tap to control')+'</small></button><button type="button" data-tv-hide="'+escape(s.service)+'" aria-label="Hide '+escape(s.name)+' from TV">×</button></div>').join(''):'<p class="kr-caption">Your open services stay here. Home never closes them.</p>';
   qa('[data-tv-focus]').forEach(b=>b.onclick=()=>send('focusMedia',{service:b.dataset.tvFocus}));
   qa('[data-tv-hide]').forEach(b=>b.onclick=()=>send('hideMedia',{service:b.dataset.tvHide}));
  }
  qa('[data-tv-focus],[data-tv-hide]').forEach(b=>b.disabled=!ok||!!state?.busy||!!tv.busy);
  q('#kr-tv-power').textContent=tv.power?'Power connected':'Plug the Mac into power for closed-lid use';
  const games=tv.games||[],key=JSON.stringify(games);
  if(signature!==key){signature=key;
   q('#kr-tv-games').innerHTML=games.length?games.map(g=>'<button type="button" class="kr-tv-game" data-tv-game="'+escape(g.id)+'" '+(g.available?'':'disabled')+'><span class="kr-tv-game-disc">◉</span><span><strong>'+escape(g.title)+'</strong><small>'+(g.available?'Play on RPCS3':'Original file missing')+'</small></span><span>›</span></button>').join(''):'<p class="kr-caption">Your RPCS3 games appear here after you start TV. Add games in RPCS3, then tap Refresh shelf.</p>';
   qa('[data-tv-game]').forEach(b=>b.onclick=()=>send('game',{game:b.dataset.tvGame}));
  }
  qa('[data-tv], [data-tv-service], #kr-tv-target, #kr-tv-trackpad, #kr-tv-add-media').forEach(b=>b.disabled=!ok||!!state?.busy||!!tv.busy||!state?.accessibility);
  qa('[data-tv-game]').forEach(b=>b.disabled=!ok||!!state?.busy||!!tv.busy||!games.find(g=>g.id===b.dataset.tvGame)?.available);
  q('#kr-tv-resume').disabled=!ok||!tv.canResume||!!state?.busy;
  q('#kr-tv-end').disabled=!ok||!tv.active||!!state?.busy;
  q('#kr-tv-share').disabled=!ok||!session.length||!!state?.busy; q('#kr-tv-focus').disabled=!ok||!session.length||!!state?.busy;
 }
 wire();return{update};
}};
