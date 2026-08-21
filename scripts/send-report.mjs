#!/usr/bin/env node
//
// Files a citizen report (ábending) with Reykjavík from the command line.
//
// This is the executable form of docs/research/payload-map.md, and the
// reference the Worker adapter gets ported from. Keeping it dependency-free and
// runnable means the payload can be re-verified in one command the day the
// city's form changes.
//
// It will NOT send anything unless you pass --send. The default builds the
// payload, resolves the location and prints exactly what would go over the
// wire. Filing a report puts work in a real queue at the city; do that
// deliberately, once, not as a test.
//
//   node scripts/send-report.mjs --category ruslafotur \
//     --photo bin.jpg --description "Full ruslafata við stíginn"
//
// Location is taken from the first photo's EXIF GPS, which is the case this
// project exists for: the bin has no address, only the coordinate that came
// with the picture. --lat/--lng or --address override it.

import { readFile } from 'node:fs/promises'
import { basename } from 'node:path'

const BASE = 'https://reykjavik.is'

// The eleven specific categories plus the one general one. Kept here rather
// than fetched so the script says what it expects and a change shows up as a
// mismatch instead of being silently absorbed.
const CATEGORIES = {
  'almenn-abending':   { type: 'general',  name: 'Almenn ábending' },
  'holur-i-gotu':      { type: 'specific', name: 'Holur í götu' },
  'heimilissorp':      { type: 'specific', name: 'Heimilissorp' },
  'snjor-og-halka':    { type: 'specific', name: 'Snjór og hálka' },
  'numerlausir-bilar': { type: 'specific', name: 'Númeralausir bílar' },
  'gras-og-grodur':    { type: 'specific', name: 'Gras og gróður' },
  'ruslafotur':        { type: 'specific', name: 'Ruslafötur' },
  'gotusopun':         { type: 'specific', name: 'Götusópun' },
  'nidurfoll':         { type: 'specific', name: 'Niðurföll' },
  'ljosastaurar':      { type: 'specific', name: 'Ljósastaurar' },
  'umferdaroryggi':    { type: 'specific', name: 'Umferðaröryggi' },
  'bilastaedasjodur':  { type: 'specific', name: 'Bílastæðasjóður' },
}

const MIME = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif' }

// ---------------------------------------------------------------- EXIF GPS

// Minimal EXIF GPS reader. Walks the JPEG segments to APP1, reads the TIFF
// header for endianness, finds the GPS IFD via tag 0x8825 in IFD0, and pulls
// the four tags that matter. Deliberately small: the app needs a coordinate out
// of a photo and nothing else out of EXIF.
function exifGps(buf) {
  if (buf.readUInt16BE(0) !== 0xffd8) return null // not a JPEG

  let off = 2
  let tiff = -1
  while (off < buf.length - 4) {
    if (buf[off] !== 0xff) break
    const marker = buf.readUInt16BE(off)
    const size = buf.readUInt16BE(off + 2)
    if (marker === 0xffe1 && buf.toString('ascii', off + 4, off + 10) === 'Exif\0\0') {
      tiff = off + 10
      break
    }
    if (marker === 0xffda) break // start of scan: no EXIF before the image data
    off += 2 + size
  }
  if (tiff < 0) return null

  const le = buf.toString('ascii', tiff, tiff + 2) === 'II'
  const u16 = (p) => (le ? buf.readUInt16LE(p) : buf.readUInt16BE(p))
  const u32 = (p) => (le ? buf.readUInt32LE(p) : buf.readUInt32BE(p))

  const readIfd = (start) => {
    const entries = new Map()
    const n = u16(start)
    for (let i = 0; i < n; i++) {
      const e = start + 2 + i * 12
      entries.set(u16(e), { type: u16(e + 2), count: u32(e + 4), valueOff: e + 8 })
    }
    return entries
  }

  const ifd0 = readIfd(tiff + u32(tiff + 4))
  const gpsPtr = ifd0.get(0x8825)
  if (!gpsPtr) return null
  const gps = readIfd(tiff + u32(gpsPtr.valueOff))

  // A rational triple (degrees, minutes, seconds) stored out of line.
  const rationals = (entry) => {
    const at = tiff + u32(entry.valueOff)
    return Array.from({ length: entry.count }, (_, i) =>
      u32(at + i * 8) / u32(at + i * 8 + 4))
  }
  const ref = (entry) => String.fromCharCode(buf[entry.valueOff])

  const lat = gps.get(0x0002), latRef = gps.get(0x0001)
  const lng = gps.get(0x0004), lngRef = gps.get(0x0003)
  if (!lat || !lng || !latRef || !lngRef) return null

  const dms = ([d, m, s]) => d + m / 60 + s / 3600
  return {
    lat: dms(rationals(lat)) * (ref(latRef) === 'S' ? -1 : 1),
    lng: dms(rationals(lng)) * (ref(lngRef) === 'W' ? -1 : 1),
  }
}

// ------------------------------------------------------------- city lookups

async function searchAddresses(q) {
  const r = await fetch(`${BASE}/location/addresses?q=${encodeURIComponent(q)}`)
  if (!r.ok) throw new Error(`address search failed: HTTP ${r.status}`)
  return (await r.json()).addresses ?? []
}

// Note the path: addressInfo lives under /abendingar/, its sibling under
// /location/. Both parameters are required; omitting either returns an error
// rather than an empty result.
async function addressInfo(address, postCode) {
  const q = new URLSearchParams({ a: address, p: String(postCode) })
  const r = await fetch(`${BASE}/abendingar/addressInfo?${q}`)
  if (!r.ok) throw new Error(`addressInfo failed: HTTP ${r.status}`)
  const body = await r.json()
  if (body.error) throw new Error(`addressInfo rejected the input: ${body.error}`)
  const hit = body.addressInfo?.[0]
  // An unregistered address returns an empty array, not an error. "Borgartún 12"
  // does this: the building is registered as "Borgartún 12-14".
  if (!hit) throw new Error(`no such address in the register: ${address}, ${postCode}`)
  return hit.geometry
}

// ------------------------------------------------------------------- args

function parseArgs(argv) {
  const out = { photos: [] }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    const next = () => argv[++i]
    switch (a) {
      case '--category':    out.category = next(); break
      case '--description': out.description = next(); break
      case '--photo':       out.photos.push(next()); break
      case '--email':       out.email = next(); break
      case '--lat':         out.lat = Number(next()); break
      case '--lng':         out.lng = Number(next()); break
      case '--address':     out.address = next(); break
      case '--postcode':    out.postcode = next(); break
      case '--send':        out.send = true; break
      case '--probe':       out.probe = true; break
      case '-h': case '--help': out.help = true; break
      default: throw new Error(`unknown argument: ${a}`)
    }
  }
  return out
}

const USAGE = `
send-report.mjs — file a report with Reykjavík, or show what would be filed

  --category <slug>     one of: ${Object.keys(CATEGORIES).join(', ')}
  --description <text>  required by the city; max 2500 characters
  --photo <path>        repeatable. jpeg, png or gif. EXIF GPS of the first
                        photo is used as the location unless overridden
  --lat <n> --lng <n>   set the coordinate explicitly
  --address <s> --postcode <n>
                        resolve the coordinate from the address register
  --email <addr>        optional; the only way to hear anything back
  --send                actually submit. Without this, nothing is sent
  --probe               post an empty payload and report how the city's
                        validation answers. Creates nothing
`

// ------------------------------------------------------------------- probe

// Posts a payload the city must reject, and reports what came back. This is the
// safe way to check the endpoint is alive and behaving: it exercises the real
// route and the real validator without creating a report.
async function probe(slug) {
  const fd = new FormData()
  fd.set('dummy', '1')
  const r = await fetch(`${BASE}/abendingar/senda-abendingu/${slug}`, { method: 'POST', body: fd })
  const text = await r.text()
  const m = text.match(/"inputErrors\\",\{[^}]*\}/) ?? text.match(/inputErrors[^,]*,([^\]]*\])/)
  console.log(`HTTP ${r.status} (expected 400)`)
  console.log(`Missing-required-fields error present: ${text.includes('Missing required fields')}`)
  console.log(`description named as an input error:   ${/\\"description\\"/.test(text)}`)
  console.log(`lat or lng named as an input error:    ${/\\"(lat|lng)\\"/.test(text)}`)
  if (m) console.log(`raw: ${m[0].slice(0, 200)}`)
  console.log('\nOnly description is enforced server-side. The relay has to reject')
  console.log('a report with no coordinate, because the city will not.')
}

// -------------------------------------------------------------------- main

async function main() {
  const args = parseArgs(process.argv.slice(2))
  if (args.help || process.argv.length === 2) return console.log(USAGE)

  const slug = args.category
  if (!slug || !CATEGORIES[slug]) {
    throw new Error(`--category must be one of: ${Object.keys(CATEGORIES).join(', ')}`)
  }
  if (args.probe) return probe(slug)

  const { type, name } = CATEGORIES[slug]

  if (!args.description) throw new Error('--description is required; the city rejects a report without one')
  if (args.description.length > 2500) throw new Error(`--description is ${args.description.length} characters; the limit is 2500`)

  // Load photos first: the location may come out of the first one.
  const photos = await Promise.all(args.photos.map(async (p) => {
    const ext = p.split('.').pop().toLowerCase()
    if (!MIME[ext]) throw new Error(`${p}: the city accepts jpeg, png and gif only`)
    return { path: p, name: basename(p), mime: MIME[ext], bytes: await readFile(p) }
  }))

  let lat = args.lat, lng = args.lng, source = 'command line'
  if (lat == null || lng == null) {
    if (args.address) {
      if (!args.postcode) throw new Error('--address needs --postcode; the register requires both')
      ;({ lat, lng } = await addressInfo(args.address, args.postcode))
      source = 'address register'
    } else if (photos.length) {
      const gps = exifGps(photos[0].bytes)
      if (gps) { ({ lat, lng } = gps); source = `EXIF GPS of ${photos[0].name}` }
    }
  }

  // The city does not enforce this. We do — see docs/research/payload-map.md.
  if (lat == null || lng == null) {
    throw new Error(
      'no location. The photo carries no EXIF GPS, so pass --lat/--lng or\n' +
      '--address/--postcode. The city would accept a report without a\n' +
      'coordinate and nobody would be able to act on it.')
  }

  const fd = new FormData()
  fd.set('type', type)
  fd.set('category', name)
  fd.set('summary', `Ábending -> ${name}`)
  fd.set('lat', String(lat))
  fd.set('lng', String(lng))
  fd.set('description', args.description)
  if (args.email) fd.set('email', args.email)
  for (const p of photos) fd.append('files', new Blob([p.bytes], { type: p.mime }), p.name)

  const url = `${BASE}/abendingar/senda-abendingu/${slug}`
  console.log(`POST ${url}`)
  for (const [k, v] of fd.entries()) {
    console.log(`  ${k.padEnd(12)} ${v instanceof Blob ? `(${v.type}, ${v.size} bytes)` : v}`)
  }
  console.log(`  location from ${source}`)

  if (!args.send) {
    console.log('\nNothing sent. Add --send to file this for real.')
    return
  }

  const r = await fetch(url, { method: 'POST', body: fd })
  const text = await r.text()
  if (r.status === 400) {
    console.error(`\nHTTP 400 — the city rejected it. inputErrors: ${/\\"description\\"/.test(text) ? 'description' : 'see response'}`)
    process.exitCode = 1
    return
  }
  if (!r.ok) {
    console.error(`\nHTTP ${r.status} — unexpected. The form may have changed; re-run the contract check.`)
    process.exitCode = 1
    return
  }
  console.log(`\nHTTP ${r.status} — filed.`)
}

main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = 1 })
