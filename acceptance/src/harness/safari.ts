import type { MacOSSandbox } from "use-computer-sdk";
import { sleep } from "./uc.js";

const enc = (s: string) => new TextEncoder().encode(s);

const RUNNER = `on run argv
	set jsPath to item 1 of argv
	set js to do shell script "cat " & quoted form of jsPath
	tell application "Safari" to do JavaScript js in front document
end run
`;

const NAVIGATE = `on run argv
	set theUrl to item 1 of argv
	tell application "Safari"
		activate
		if (count of documents) = 0 then
			make new document with properties {URL:theUrl}
		else
			set URL of front document to theUrl
		end if
	end tell
end run
`;

/**
 * DOM helper injected before each interaction. Uses the native value setter so React's
 * controlled inputs register changes, and matches elements by visible text / placeholder /
 * aria-label so tests key off the real UI strings (from acceptance/features/web.md).
 */
const HELPER = `window.__cap = (function(){
  function vis(el){ if(!el) return false; var r=el.getBoundingClientRect(); return r.width>0 && r.height>0; }
  function clickables(){ return Array.prototype.slice.call(document.querySelectorAll('button,[role=button],a,summary,label,input[type=submit]')); }
  function byText(t, exact, last){ t=(t||'').trim(); var els=clickables().filter(vis); var hit=els.filter(function(e){var x=(e.textContent||'').trim(); return exact? x===t : x.indexOf(t)>=0;}); return last? (hit[hit.length-1]||null) : (hit[0]||null); }
  function setNativeValue(el, value){
    var proto = el.tagName==='TEXTAREA'? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
    var setter = Object.getOwnPropertyDescriptor(proto,'value').set; setter.call(el, value);
    el.dispatchEvent(new Event('input',{bubbles:true}));
    el.dispatchEvent(new Event('change',{bubbles:true}));
  }
  function field(sel){
    var el = document.querySelector(sel);
    if(el) return el;
    // fall back: placeholder / aria-label / associated label text contains sel
    var inputs = Array.prototype.slice.call(document.querySelectorAll('input,textarea')).filter(vis);
    return inputs.filter(function(i){
      return (i.placeholder||'').toLowerCase().indexOf(sel.toLowerCase())>=0 ||
             (i.getAttribute('aria-label')||'').toLowerCase().indexOf(sel.toLowerCase())>=0;
    })[0]||null;
  }
  return {
    ready: function(host){ var r=document.getElementById('root'); return document.readyState==='complete' && !!r && r.children.length>0 && location.href.indexOf(host)>=0; },
    text: function(){ return (document.body? document.body.innerText: '').replace(/\\u00a0/g,' '); },
    has: function(t){ return this.text().indexOf(t)>=0; },
    hasValue: function(t){ return Array.prototype.slice.call(document.querySelectorAll('input,textarea')).some(function(i){return (i.value||'').indexOf(t)>=0;}); },
    count: function(sel){ return document.querySelectorAll(sel).length; },
    clickText: function(t, exact, last){ var e=byText(t, exact, last); if(!e) return 'NOFIND:'+t; e.scrollIntoView({block:'center'}); e.click(); return 'OK'; },
    submit: function(t){ var e=byText(t, true, true) || document.querySelector('form button[type=submit]'); if(!e) return 'NOFIND:'+t; e.scrollIntoView({block:'center'}); e.click(); return 'OK'; },
    click: function(sel){ var e=document.querySelector(sel); if(!e) return 'NOFIND:'+sel; e.scrollIntoView({block:'center'}); e.click(); return 'OK'; },
    type: function(sel, value){ var e=field(sel); if(!e) return 'NOFIND:'+sel; e.focus(); setNativeValue(e, value); return 'OK'; },
    submitEnter: function(sel){ var e=field(sel)||document.activeElement; if(!e) return 'NOEL'; e.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true})); e.dispatchEvent(new KeyboardEvent('keyup',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true})); return 'OK'; },
    capture: function(text){
      var inp = Array.prototype.slice.call(document.querySelectorAll('input')).filter(function(i){return (i.placeholder||'').toLowerCase().indexOf('capture anything')>=0;})[0];
      if(!inp) return 'NOINPUT';
      inp.focus(); setNativeValue(inp, text);
      var bar = inp.closest('.capture-bar') || inp.parentElement;
      var btn = bar && Array.prototype.slice.call(bar.querySelectorAll('button')).filter(function(b){return /Capture/.test(b.textContent);})[0];
      if(btn){ btn.click(); return 'CLICK'; }
      inp.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',keyCode:13,which:13,bubbles:true}));
      return 'ENTER';
    },
    signedIn: function(){ return this.has('Manage labels') || this.count('.capture-bar')>0; },
    buttons: function(){ return JSON.stringify(clickables().filter(vis).map(function(e){return (e.textContent||'').trim();}).filter(Boolean).slice(0,40)); },
    placeholders: function(){ return JSON.stringify(Array.prototype.slice.call(document.querySelectorAll('input,textarea')).map(function(i){return i.placeholder;}).filter(Boolean)); }
  };
})(); 'HELPER_OK'`;

export class Safari {
  constructor(private readonly mac: MacOSSandbox, private readonly host: string) {}

  /** One-time per-sandbox setup: allow AppleScript JS + dismiss notification chrome. */
  async setup(): Promise<void> {
    await this.mac.execSsh(`defaults write com.apple.Safari IncludeDevelopMenu -bool true`);
    await this.mac.execSsh(`defaults write com.apple.Safari AllowJavaScriptFromAppleEvents -bool true`);
    await this.mac.execSsh(`osascript -e 'tell application "Safari" to quit' >/dev/null 2>&1 || true`);
    await sleep(2000);
    await this.mac.execSsh("mkdir -p /tmp/capture");
    await this.mac.upload(enc(RUNNER), "/tmp/capture/run.applescript");
    await this.mac.upload(enc(NAVIGATE), "/tmp/capture/nav.applescript");
    await this.dismissChrome();
  }

  /** Best-effort dismissal of the update/tips banners and TCC dialogs that overlay the app. */
  async dismissChrome(): Promise<void> {
    await this.mac.execSsh(`osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true`);
  }

  /** Raw JS eval in the front document; returns the string result. */
  async js(code: string, id = "step"): Promise<string> {
    await this.mac.upload(enc(code), `/tmp/capture/${id}.js`);
    const r = await this.mac.execSsh(`osascript /tmp/capture/run.applescript /tmp/capture/${id}.js`, 60_000);
    if (r.exitCode !== 0) throw new Error(`js(${id}) exit ${r.exitCode}: ${r.stderr.slice(0, 200)}`);
    return r.stdout.trim();
  }

  /** Navigate the front document and wait until the SPA has mounted (#root populated). */
  async open(path = "/"): Promise<void> {
    const url = this.host.replace(/\/$/, "") + path;
    await this.mac.execSsh(`osascript /tmp/capture/nav.applescript ${JSON.stringify(url)}`);
    const hostOnly = this.host.replace(/^https?:\/\//, "").replace(/\/.*$/, "");
    for (let i = 0; i < 40; i++) {
      await sleep(1500);
      await this.inject();
      const ready = await this.js(`window.__cap && __cap.ready(${JSON.stringify(hostOnly)}) ? 'READY':'WAIT'`, "ready").catch(() => "WAIT");
      if (ready === "READY") return;
    }
    throw new Error(`web app did not mount at ${url}`);
  }

  private async inject(): Promise<void> {
    await this.js(HELPER, "helper").catch(() => {});
  }

  async text(): Promise<string> {
    await this.inject();
    return this.js("__cap.text()", "text");
  }
  async has(needle: string): Promise<boolean> {
    await this.inject();
    return (await this.js(`String(__cap.has(${JSON.stringify(needle)}))`, "has")) === "true";
  }
  /** True if any input/textarea value contains the needle (confirm-card titles are input values). */
  async hasValue(needle: string): Promise<boolean> {
    await this.inject();
    return (await this.js(`String(__cap.hasValue(${JSON.stringify(needle)}))`, "hasval")) === "true";
  }
  async buttons(): Promise<string[]> {
    await this.inject();
    return JSON.parse(await this.js("__cap.buttons()", "btns"));
  }
  async clickText(text: string, exact = true, last = false): Promise<void> {
    await this.inject();
    const r = await this.js(`__cap.clickText(${JSON.stringify(text)}, ${exact}, ${last})`, "clicktext");
    if (r.startsWith("NOFIND")) throw new Error(`clickText: not found "${text}"`);
  }
  /** Click a form submit (or the LAST button with the given label, to avoid tab/submit ambiguity). */
  async submit(text: string): Promise<void> {
    await this.inject();
    const r = await this.js(`__cap.submit(${JSON.stringify(text)})`, "submit");
    if (r.startsWith("NOFIND")) throw new Error(`submit: not found "${text}"`);
  }
  async click(selector: string): Promise<void> {
    await this.inject();
    const r = await this.js(`__cap.click(${JSON.stringify(selector)})`, "click");
    if (r.startsWith("NOFIND")) throw new Error(`click: not found "${selector}"`);
  }
  async type(selectorOrPlaceholder: string, value: string): Promise<void> {
    await this.inject();
    const r = await this.js(`__cap.type(${JSON.stringify(selectorOrPlaceholder)}, ${JSON.stringify(value)})`, "type");
    if (r.startsWith("NOFIND")) throw new Error(`type: field not found "${selectorOrPlaceholder}"`);
  }
  async submitEnter(selectorOrPlaceholder = ""): Promise<void> {
    await this.inject();
    await this.js(`__cap.submitEnter(${JSON.stringify(selectorOrPlaceholder)})`, "enter");
  }
  /** Set the capture-bar value and submit (clicks the "Capture ⏎" button; Enter fallback). */
  async capture(text: string): Promise<void> {
    await this.inject();
    const r = await this.js(`__cap.capture(${JSON.stringify(text)})`, "capture");
    if (r === "NOINPUT") throw new Error("capture bar input not found");
  }
  async signedIn(): Promise<boolean> {
    await this.inject();
    return (await this.js("String(__cap.signedIn())", "signedin")) === "true";
  }
  async count(selector: string): Promise<number> {
    await this.inject();
    return Number(await this.js(`String(__cap.count(${JSON.stringify(selector)}))`, "count"));
  }
  async screenshot(): Promise<Uint8Array> {
    return this.mac.screenshot.takeCompressed();
  }

  /** Poll until the page text contains `needle` (for async sync/enrichment landing). */
  async waitForText(needle: string, timeoutMs = 30_000): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (await this.has(needle)) return true;
      await sleep(2000);
    }
    return false;
  }
}
