/**
 * Gera as imagens de prévia (Open Graph) do site a partir de `template.html`.
 *
 * Rode `node _og/gerar.mjs` depois de mudar o modelo e commite os JPEGs de
 * `og/` junto. Elas são estáticas de propósito: o GitHub Pages só serve os
 * arquivos. Mesmo gerador da documentação (MonkyOrg/Monky, `docs-site/og/`).
 *
 * Usa o Chrome ou o Edge instalado, pelo protocolo DevTools, porque só ele
 * entrega JPEG — o `--screenshot` da linha de comando salva PNG, e os apps de
 * mensagem descartam imagens grandes. Aponte `CHROME_BIN` para outro binário
 * se o seu não estiver num caminho conhecido. Precisa de internet: as fontes
 * vêm do Google Fonts (este repositório não tem `node_modules`).
 */
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const output = resolve(here, '..', 'og');
const template = pathToFileURL(join(here, 'template.html')).href;
const languages = ['pt', 'en'];
const width = 1200;
const height = 630;
const maxBytes = 300 * 1024;

function findBrowser() {
  const candidates = [
    process.env.CHROME_BIN,
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
  ];
  const found = candidates.find(candidate => candidate && existsSync(candidate));
  if (!found) throw new Error('Chrome/Edge não encontrado. Defina CHROME_BIN com o caminho do executável.');
  return found;
}

function launch(binary, profile) {
  const child = spawn(binary, [
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    '--no-first-run',
    '--no-default-browser-check',
    '--allow-file-access-from-files',
    `--user-data-dir=${profile}`,
    '--remote-debugging-port=0',
    'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  return new Promise((resolvePort, reject) => {
    let log = '';
    const timer = setTimeout(() => reject(new Error(`O navegador não abriu a porta de depuração:\n${log}`)), 15_000);
    child.stderr.on('data', chunk => {
      log += chunk;
      const match = /DevTools listening on ws:\/\/[^:]+:(\d+)\//.exec(log);
      if (match) {
        clearTimeout(timer);
        resolvePort({ child, port: Number(match[1]) });
      }
    });
    child.once('exit', code => reject(new Error(`O navegador saiu com o código ${code}:\n${log}`)));
  });
}

function connect(url) {
  const socket = new WebSocket(url);
  let nextId = 0;
  const pending = new Map();
  const listeners = new Map();
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id !== undefined) {
      const request = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) request.reject(new Error(`${message.error.message} (${request.method})`));
      else request.resolve(message.result);
    } else {
      listeners.get(message.method)?.(message.params);
    }
  });
  const send = (method, params = {}) => new Promise((resolveSend, reject) => {
    const id = ++nextId;
    pending.set(id, { resolve: resolveSend, reject, method });
    socket.send(JSON.stringify({ id, method, params }));
  });
  const once = method => new Promise(resolveOnce => listeners.set(method, resolveOnce));
  return new Promise((resolveOpen, reject) => {
    socket.addEventListener('open', () => resolveOpen({ send, once, close: () => socket.close() }));
    socket.addEventListener('error', () => reject(new Error(`Falha ao conectar em ${url}`)));
  });
}

async function render(page, language) {
  const loaded = page.once('Page.loadEventFired');
  await page.send('Page.navigate', { url: `${template}?lang=${language}` });
  await loaded;
  // O Google Fonts declara vários subconjuntos; só os usados carregam. Por isso
  // pede as fontes explicitamente e confere com `check` em vez de exigir todas.
  const { result, exceptionDetails } = await page.send('Runtime.evaluate', {
    expression: `(async () => {
      const wanted = ['800 132px Inter', '600 38px Inter', '48px "Material Symbols Outlined"'];
      const sample = document.body.innerText;
      await Promise.all(wanted.map(font => document.fonts.load(font, sample)));
      await document.fonts.ready;
      await Promise.all([...document.images].map(image => image.decode()));
      return wanted.filter(font => !document.fonts.check(font, sample));
    })()`,
    awaitPromise: true,
    returnByValue: true,
  });
  if (exceptionDetails) throw new Error(`O modelo falhou em ${language}: ${exceptionDetails.text}`);
  if (result.value.length) throw new Error(`Fontes não carregadas: ${result.value.join(', ')}. Verifique a internet.`);
  const { data } = await page.send('Page.captureScreenshot', { format: 'jpeg', quality: 88 });
  return Buffer.from(data, 'base64');
}

const profile = mkdtempSync(join(tmpdir(), 'monkyorg-og-'));
const { child, port } = await launch(findBrowser(), profile);
try {
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const target = targets.find(item => item.type === 'page');
  const page = await connect(target.webSocketDebuggerUrl);
  await page.send('Page.enable');
  await page.send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
  mkdirSync(output, { recursive: true });
  for (const language of languages) {
    const file = join(output, `home-${language}.jpg`);
    const image = await render(page, language);
    if (image.length > maxBytes) throw new Error(`${file} ficou com ${Math.round(image.length / 1024)} KB; o WhatsApp descarta acima de ~300 KB.`);
    writeFileSync(file, image);
    console.log(`${file} (${Math.round(image.length / 1024)} KB)`);
  }
  page.close();
} finally {
  const exited = new Promise(resolveExit => child.once('exit', resolveExit));
  child.kill();
  await exited;
  // No Windows o perfil fica travado por um instante depois que o processo sai
  // (o Edge deixa processos filhos); se ainda assim falhar, só avisa.
  try {
    rmSync(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 250 });
  } catch (error) {
    console.warn(`Não consegui apagar o perfil temporário ${profile}: ${error.code}`);
  }
}
