#!/usr/bin/env node
//
// Posts the exact multipart request the Android app builds at the relay
// (http://127.0.0.1:8787/api/reports). The relay is in dry run by default and
// forwards nothing to the city, so this is safe against a local worker:
//
//   node scripts/post-relay-request.mjs             # the request the app builds today
//   node scripts/post-relay-request.mjs --old-app   # the pre-contract request (the city's
//                                                   # vocabulary), which the relay must reject
//
// The wire format mirrors android/app/src/main/kotlin/is/borgarland/net/RelayClient.kt
// byte for byte: the same boundary scheme, the same part order (the contract's
// field order), the same CRLF handling and UTF-8 text parts. The photo is a
// realistic 1.1 MB JPEG with the JFIF magic, named mynd.jpg, matching the app's
// capture (PocViewModel.onPhotoCaptured names every photo mynd.jpg).
//
// It never touches reykjavik.is. The only URL in this script is the relay's.

import { readFile } from 'node:fs/promises'

const BASE = 'http://127.0.0.1:8787'

// The relay's coordinate for Laugavegur 1 (registry fixture), so the
// jurisdiction check passes. The app would send whatever EXIF GPS or the
// device fix produced; this is a fixed stand-in for a real report.
const VALUES = {
  category: 'ruslafotur',
  latitude: '64.14658919',
  longitude: '-21.93279823',
  description: 'Full ruslafata við stíginn',
  // Where the city sends its confirmation (#163). Required by the contract, so
  // the loop below refuses to build a request without it — exactly as the app
  // does. The app reads this from the phone; here it is a stand-in.
  email: 'prufa@example.is',
}

function photoBytes() {
  const size = 1_153_600 // 1.1 MB
  const buf = Buffer.alloc(size)
  buf.set([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01]) // JFIF
  buf[size - 2] = 0xff
  buf[size - 1] = 0xd9 // EOI
  return buf
}

async function main() {
  const oldApp = process.argv.includes('--old-app')
  const contract = oldApp
    ? null
    : JSON.parse(await readFile(new URL('../data/relay-request.json', import.meta.url), 'utf8'))

  const boundary = `----borgarland${Date.now()}`
  const chunks = []

  function field(name, value) {
    chunks.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n`, 'utf8'))
    chunks.push(Buffer.from(value, 'utf8'))
    chunks.push(Buffer.from('\r\n', 'utf8'))
  }

  function photo(name) {
    chunks.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="${name}"; filename="mynd.jpg"\r\n` +
          'Content-Type: image/jpeg\r\n\r\n',
        'utf8',
      ),
    )
    chunks.push(photoBytes())
    chunks.push(Buffer.from('\r\n', 'utf8'))
  }

  let partsLabel
  if (oldApp) {
    // The request the app built before the contract: the city's vocabulary.
    field('type', 'specific')
    field('category', 'Ruslafötur')
    field('summary', 'Ábending -> Ruslafötur')
    field('lat', VALUES.latitude)
    field('lng', VALUES.longitude)
    field('description', VALUES.description)
    photo('files')
    partsLabel = 'type, category, summary, lat, lng, description, files'
  } else {
    // The request the app builds now: the contract's field names, in its order.
    for (const [name, spec] of Object.entries(contract.fields)) {
      if (name === 'photo') {
        photo('photo')
        continue
      }
      const value = VALUES[name]
      // The app's own refusal, mirrored: a required part it cannot fill stops
      // the request before a byte of body exists (RelayClient.kt, and
      // MultipartBodyBuilder.swift). Without this the loop SILENTLY omitted a
      // field it had no value for, so this script could keep claiming to build
      // "the request the app builds" while building one the app would refuse —
      // which is what it did for as long as it took to notice, when email
      // became required.
      if (spec.required && value === undefined) {
        throw new Error(
          `relay contract field '${name}' is required and this script has no value for it; ` +
            'add one to VALUES rather than letting the part be dropped',
        )
      }
      if (value !== undefined) field(name, value)
    }
    partsLabel = Object.keys(contract.fields).join(', ')
  }
  chunks.push(Buffer.from(`--${boundary}--\r\n`, 'utf8'))

  const response = await fetch(`${BASE}${contract?.endpoint?.path ?? '/api/reports'}`, {
    method: 'POST',
    headers: { 'Content-Type': `multipart/form-data; boundary=${boundary}` },
    body: Buffer.concat(chunks),
  })
  const text = await response.text()

  console.log(`HTTP ${response.status}${oldApp ? ' — the pre-contract app request' : ' — the app request'}`)
  console.log(`parts: ${partsLabel}`)
  console.log(`photo part name: ${oldApp ? 'files' : 'photo'}; filename mynd.jpg; ${photoBytes().length} bytes; image/jpeg`)
  console.log('---')
  console.log(text.length > 2000 ? `${text.slice(0, 2000)}\n… (${text.length} bytes)` : text)
}

main().catch((e) => {
  console.error(`error: ${e.message}`)
  process.exitCode = 1
})
