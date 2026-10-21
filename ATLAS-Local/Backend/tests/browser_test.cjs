// Developer-only: requires Playwright and its Chromium browser.
const {chromium}=require('playwright');
const {spawn}=require('node:child_process');
const assert=require('node:assert/strict');
const path=require('node:path');
(async()=>{
 const fixture=spawn('python3',['-u',path.join(__dirname,'browser_fixture.py')]);
 fixture.stderr.on('data',d=>process.stderr.write(d));
 let browser;
 try{
  const port=await new Promise((resolve,reject)=>{fixture.stdout.once('data',d=>resolve(Number(d.toString().trim())));fixture.once('error',reject);fixture.once('exit',c=>reject(Error('fixture exit '+c)));});
  browser=await chromium.launch({headless:true,executablePath:process.env.ATLAS_TEST_BROWSER||undefined,args:[...JSON.parse(process.env.ATLAS_TEST_BROWSER_ARGS||'[]'),'--use-fake-ui-for-media-stream','--use-fake-device-for-media-stream']});
  const context=await browser.newContext({permissions:['microphone']});const page=await context.newPage();
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(`http://127.0.0.1:${port}`);
  await page.waitForFunction(()=>document.getElementById('notice').textContent.includes('Ollama bereit'));
  console.log('PASS UI startup and health');
  await page.fill('#message','Hallo');await page.click('#send');
  await page.waitForFunction(()=>document.querySelector('.assistant')?.textContent==='Hallo ');
  assert.equal(await page.locator('#send').isDisabled(),true);
  await page.waitForFunction(()=>document.getElementById('metrics').textContent.includes('Erster Text'));
  assert.equal(await page.locator('.assistant').last().textContent(),'Hallo Robin. Lokal getestet.');
  console.log('PASS progressive streaming and timing display');
  await page.fill('#memory-input','<img src=x onerror=alert(1)>');await page.locator('#memory-form button').click();
  await page.waitForFunction(()=>document.getElementById('notice').textContent==='Gespeichert');
  assert.equal(await page.locator('#memories img').count(),0);
  await page.reload();await page.waitForSelector('.memory');
  assert.match(await page.locator('.memory').textContent(),/onerror/);
  console.log('PASS memory persistence and literal HTML rendering');
  await page.fill('#message','langsam');await page.click('#send');
  await page.waitForFunction(()=>[...document.querySelectorAll('.assistant')].at(-1).textContent.includes('Weiter'));
  await page.click('#stop');await page.waitForFunction(()=>document.getElementById('notice').textContent.includes('gestoppt'));
  assert.match(await page.locator('.assistant').last().textContent(),/Unvollständig/);
  console.log('PASS abort and incomplete-answer indication');
  await page.waitForTimeout(250); // synthetic fixture token interval, not a production wait
  page.once('dialog',d=>d.accept());await page.click('#clear');
  await page.waitForFunction(()=>document.getElementById('notice').textContent==='Verlauf gelöscht');
  await page.click('#speak');await page.waitForFunction(()=>document.getElementById('notice').textContent.includes('keine vollständige'));
  assert.equal(await page.locator('.bubble').count(),0);
  console.log('PASS clear resets speech state');
  page.once('dialog',d=>d.dismiss());await page.click('#action');
  await page.waitForFunction(()=>document.getElementById('notice').textContent==='Abgebrochen');
  page.once('dialog',d=>d.accept());await page.click('#action');
  await page.waitForFunction(()=>document.getElementById('notice').textContent==='Aktion ausgeführt');
  console.log('PASS action cancel and confirm workflow (mock OS)');
  await page.click('#mic');await page.waitForFunction(()=>document.getElementById('mic').textContent==='⏹️');
  await page.waitForTimeout(400);await page.click('#mic');
  await page.waitForFunction(()=>document.getElementById('message').value==='Aufnahme erkannt');
  console.log('PASS fake microphone recording, stop and transcription UI (mock STT)');
  await page.check('#autosend');await page.check('#autoread');await page.click('#mic');
  await page.waitForFunction(()=>document.getElementById('mic').textContent==='⏹️');await page.waitForTimeout(400);await page.click('#mic');
  await page.waitForFunction(()=>document.getElementById('metrics').textContent.includes('Erster Text'));
  await page.waitForFunction(()=>!document.getElementById('send').disabled);
  assert.equal(await page.locator('.user').last().textContent(),'Aufnahme erkannt');
  console.log('PASS optional auto-send and auto-speak flow (mock OS/STT)');
  assert.deepEqual(errors,[]);console.log('PASS no browser JavaScript errors');
 }finally{if(browser)await browser.close();fixture.kill('SIGTERM');}
})().catch(e=>{console.error(e);process.exitCode=1;});
