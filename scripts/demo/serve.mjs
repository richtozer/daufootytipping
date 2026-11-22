#!/usr/bin/env node
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { repoRoot } from './generate.mjs';

const server = createServer((request, response) => {
  const path = new URL(request.url, 'http://localhost').pathname;
  const avatar = /^\/avatars\/([a-z]+\.jpg)$/.exec(path);
  const fixture = /^\/fixtures\/((afl|nrl)-2026\.json)$/.exec(path);
  if (request.method !== 'GET' || (!avatar && !fixture)) {
    response.writeHead(404).end(); return;
  }
  try {
    const file = avatar ? resolve(repoRoot, 'demo/avatars', avatar[1]) : resolve(repoRoot, 'emulator/demo/fixtures', fixture[1]);
    const bytes = readFileSync(file);
    response.writeHead(200, {
      'Content-Type': avatar ? 'image/jpeg' : 'application/json',
      'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-cache',
    });
    response.end(bytes);
  } catch {
    response.writeHead(404).end();
  }
});
server.listen(8765, '127.0.0.1', () => console.log('Demo avatars and shifted fixtures: http://127.0.0.1:8765'));
