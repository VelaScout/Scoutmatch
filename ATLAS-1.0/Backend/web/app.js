'use strict';
const $=id=>document.getElementById(id);
let initialized=false;
let lastAnswer='', busy=false, recording=false, transcribing=false, micPending=false;
let recorder=null, stream=null, timer=null, controller=null, requestId=null;
const headers={'Content-Type':'application/json','X-Atlas-Token':window.ATLAS_TOKEN};
function notice(text){$('notice').textContent=text;}
async function api(path,data={}){
  const response=await fetch('/api/'+path,{method:'POST',headers,body:JSON.stringify(data)});
  const result=await response.json();if(!response.ok)throw Error(result.error||'Anfrage fehlgeschlagen');return result;
}
function updateControls(){
  $('send').disabled=!initialized||busy||recording||transcribing;
  document.querySelectorAll('#memory-form input, #memory-form button, #memories button').forEach(el=>el.disabled=busy);
  $('clear').disabled=busy;
  $('model').disabled=busy;
  $('stop').hidden=!busy;
  $('mic').disabled=busy||transcribing||micPending||!$('mic').dataset.ready;
}
function bubble(role,text){
  const div=document.createElement('div');div.className='bubble '+role;div.textContent=text;
  $('chat').appendChild(div);$('chat').scrollTop=$('chat').scrollHeight;return div;
}
async function refresh(){
  const response=await fetch('/api/state');const state=await response.json();
  if(!response.ok)throw Error(state.error||'Atlas nicht erreichbar');
  lastAnswer='';$('chat').replaceChildren();
  state.messages.forEach(m=>{bubble(m.role,m.content);if(m.role==='assistant')lastAnswer=m.content;});
  $('memories').replaceChildren();
  for(const m of state.memories){
    const d=document.createElement('div');d.className='memory';d.textContent=m.content;
    const b=document.createElement('button');b.textContent='×';b.title='Erinnerung löschen';
    b.onclick=()=>safe(async()=>{if(confirm('Erinnerung löschen?')){await api('memory/delete',{id:m.id});await refresh();}});
    d.appendChild(b);$('memories').appendChild(d);
  }
  $('mic').dataset.ready=state.voice_ready?'yes':'';
  $('mic').title=state.voice_ready?'Aufnahme starten':'Spracherkennung nicht eingerichtet';
  $('connection').textContent='Atlas verbunden · lokal';updateControls();
}
async function health(){
  const r=await fetch('/api/health');const s=await r.json();
  if(!s.ollama){notice(s.error||'Ollama ist nicht erreichbar');$('connection').textContent='Ollama offline';return;}
  for(const opt of $('model').options)opt.disabled=!s.models.includes(opt.value);
  if(!$('model').selectedOptions[0]||$('model').selectedOptions[0].disabled){
    const available=[...$('model').options].find(x=>!x.disabled);if(available)$('model').value=available.value;
  }
  notice(s.models.length?'Ollama bereit · '+s.models.join(', '):'Kein unterstütztes Modell installiert.');
}
async function safe(fn){try{await fn();}catch(e){notice(e.message);}}
function metricText(m){return `Erster Text: ${m.first_token_s} s · Gesamt: ${m.total_s} s · Modellladen: ${m.load_s} s`+(m.tokens_per_s?` · ${m.tokens_per_s} Token/s`:'');}
async function sendMessage(){
  if(!initialized||busy||recording||transcribing)return;
  const text=$('message').value.trim();if(!text)return;
  busy=true;updateControls();$('message').value='';$('metrics').textContent='';
  bubble('user',text);const answer=bubble('assistant','');answer.classList.add('partial');
  notice('Modell bereitet die Antwort vor …');$('status').textContent='Atlas antwortet';
  controller=new AbortController();requestId=crypto.randomUUID();let completed=false,elapsed=0;
  const clock=setInterval(()=>{elapsed++;if(!answer.textContent)notice(`Warte auf erste Wörter … ${elapsed} s (beim ersten Mal wird das Modell geladen)`);},1000);
  try{
    const r=await fetch('/api/chat/stream',{method:'POST',headers,signal:controller.signal,
      body:JSON.stringify({message:text,model:$('model').value,request_id:requestId})});
    if(!r.ok){const e=await r.json();throw Error(e.error);}
    const reader=r.body.getReader();const decoder=new TextDecoder();let buffer='';
    function event(e){
      if(e.type==='delta'){answer.textContent+=e.text;notice('');$('chat').scrollTop=$('chat').scrollHeight;}
      if(e.type==='done'){
        completed=true;answer.textContent=e.answer;answer.classList.remove('partial');lastAnswer=e.answer;
        $('metrics').textContent=metricText(e.metrics);notice(e.truncated?'Antwortlänge erreicht. Frage bei Bedarf nach einer Fortsetzung.':'');
      }
      if(e.type==='cancelled')throw new DOMException('Gestoppt','AbortError');
      if(e.type==='error')throw Error(e.error);
    }
    while(true){
      const part=await reader.read();buffer+=decoder.decode(part.value||new Uint8Array(),{stream:!part.done});
      let split;while((split=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,split);buffer=buffer.slice(split+1);if(line.trim())event(JSON.parse(line));}
      if(part.done)break;
    }
    if(buffer.trim())event(JSON.parse(buffer));
    if(!completed)throw Error('Verbindung vor Ende der Antwort geschlossen.');
    if($('autoread').checked)await api('speak',{text:lastAnswer});
  }catch(e){
    if(!completed){answer.textContent+=(answer.textContent?'\n\n':'')+'[Unvollständig – nicht gespeichert]';$('message').value=text;}
    notice(e.name==='AbortError'?'Antwort gestoppt. Der lokale Auftrag wird beendet.':e.message);
  }finally{clearInterval(clock);busy=false;controller=null;requestId=null;$('status').textContent='Bereit';updateControls();}
}
$('form').onsubmit=e=>{e.preventDefault();safe(sendMessage);};
$('stop').onclick=()=>safe(async()=>{const id=requestId;controller?.abort();if(id)await api('chat/cancel',{request_id:id});});
$('health').onclick=()=>safe(health);
$('model').onchange=()=>notice('Gewähltes Modell: '+$('model').value+'. Beim Wechsel kann erneutes Laden nötig sein.');
$('memory-form').onsubmit=e=>{e.preventDefault();safe(async()=>{if(busy)throw Error('Bitte die laufende Antwort abwarten.');const value=$('memory-input').value.trim();if(value){await api('memory',{content:value});$('memory-input').value='';await refresh();notice('Gespeichert');}});};
$('clear').onclick=()=>safe(async()=>{if(confirm('Chatverlauf löschen? Erinnerungen bleiben erhalten.')){await api('clear');await refresh();notice('Verlauf gelöscht');}});
$('speak').onclick=()=>safe(async()=>{if(!lastAnswer)throw Error('Noch keine vollständige Antwort vorhanden.');await api('speak',{text:lastAnswer});notice('Sprachausgabe gestartet');});
$('silence').onclick=()=>safe(async()=>{await api('speak/stop');notice('Sprachausgabe gestoppt');});
const targets={app:[['finder','Finder'],['calculator','Rechner'],['notes','Notizen'],['calendar','Kalender'],['safari','Safari'],['textedit','TextEdit']],folder:[['downloads','Downloads'],['desktop','Schreibtisch'],['documents','Dokumente']]};
function setTargets(){ $('target').replaceChildren();for(const [value,label] of targets[$('kind').value]){const option=document.createElement('option');option.value=value;option.textContent=label;$('target').appendChild(option);}}
$('kind').onchange=setTargets;setTargets();
$('action').onclick=()=>safe(async()=>{const r=await api('action/request',{kind:$('kind').value,target:$('target').value});const result=await api('action/confirm',{token:r.token,approved:confirm(r.description)});notice(result.message);});
function releaseMic(){clearTimeout(timer);if(stream)stream.getTracks().forEach(t=>t.stop());stream=null;recording=false;micPending=false;$('mic').textContent='🎙️';$('mic').setAttribute('aria-label','Aufnahme starten');}
$('mic').onclick=()=>safe(async()=>{
  if(recording){recorder.stop();return;}
  if(busy||transcribing||micPending)return;
  micPending=true;updateControls();
  try{
    if(!navigator.mediaDevices?.getUserMedia||!window.MediaRecorder)throw Error('Dieser Browser unterstützt die Aufnahme nicht.');
    await api('speak/stop'); // Prevent Atlas transcribing its own voice.
    stream=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true}});
    const mime=['audio/webm;codecs=opus','audio/mp4'].find(t=>MediaRecorder.isTypeSupported(t));
    const active=new MediaRecorder(stream,mime?{mimeType:mime}:undefined);recorder=active;const chunks=[];
    active.ondataavailable=e=>{if(e.data.size)chunks.push(e.data);};
    active.onerror=()=>{releaseMic();notice('Aufnahme fehlgeschlagen. Bitte erneut versuchen.');updateControls();};
    active.onstop=async()=>{
      releaseMic();transcribing=true;updateControls();notice('Sprache wird lokal erkannt …');
      let send=false;
      try{
        const blob=new Blob(chunks,{type:active.mimeType});
        if(!blob.size)throw Error('Keine Audiodaten aufgenommen.');
        const response=await fetch('/api/transcribe?language='+$('language').value,{method:'POST',headers:{'X-Atlas-Token':window.ATLAS_TOKEN,'Content-Type':blob.type||'application/octet-stream'},body:blob});
        const result=await response.json();if(!response.ok)throw Error(result.error);
        $('message').value=result.text;notice(result.text?`Erkannt in ${result.seconds} s. Text prüfen und senden.`:result.message||'Keine Sprache erkannt.');
        send=Boolean(result.text)&&$('autosend').checked;
      }catch(e){notice(e.message);}finally{transcribing=false;updateControls();}
      if(send)await sendMessage();
    };
    active.start();recording=true;micPending=false;updateControls();$('mic').textContent='⏹️';$('mic').setAttribute('aria-label','Aufnahme stoppen');notice('Aufnahme läuft. Erneut klicken zum Stoppen (max. 30 s).');
    timer=setTimeout(()=>{if(active.state==='recording')active.stop();},30000);
  }catch(e){releaseMic();updateControls();throw e;}
});
window.addEventListener('pagehide',releaseMic);
updateControls();
safe(async()=>{await refresh();await health();initialized=true;updateControls();});
