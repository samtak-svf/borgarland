// Identifying an image from its leading bytes, because the relay must know
// what a photo actually is, not what its Content-Type claims it is.
//
// The declared type is the only thing the city ever sees — the city validates
// nothing about the bytes behind it (see data/reykjavik-form.json) — and an
// iPhone shoots HEIC, a format the city does not accept. A HEIC file declared
// as image/jpeg therefore passes the type allowlist in app.ts and then fails
// the city's own validation, after the report has already been recorded as
// sent. The relay sniffs the bytes and refuses the mismatch instead, so the
// reporter finds out before anything is filed.
//
// Every signature is from the format's specification, cross-checked against
// the file(1) magic database (file-5.46, /usr/share/file/magic). The HEIF
// brand list is the one the ISO/IEC 23008-12 spec and the nokiatech reference
// implementation agree on (the magic database cites both). A brand missing
// from the set reads as unrecognised and is rejected, which is the safe
// failure for a relay that cannot forward HEIC anyway.
//
// The reverse mistake is the costly one: a signature that is too generous
// rejects a valid photo, which is worse than the bug being fixed. All the
// signatures below match the leading bytes of a genuine file of that format
// and nothing else.

const JPEG_SIGNATURE = [0xff, 0xd8, 0xff]
const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
const GIF_SIGNATURES = [
  [0x47, 0x49, 0x46, 0x38, 0x37, 0x61], // 'GIF87a'
  [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], // 'GIF89a'
]
const BMP_SIGNATURE = [0x42, 0x4d] // 'BM'
const TIFF_SIGNATURES = [
  [0x49, 0x49, 0x2a, 0x00], // 'II*\0', little-endian
  [0x4d, 0x4d, 0x00, 0x2a], // 'MM\0*', big-endian
]

// ISO/IEC 23008-12 major brands of a HEIF file. 'heic' and 'heix' are what an
// iPhone writes; the others cover the remaining HEVC profiles and the generic
// mif1/msf1 containers. All map to image/heic because that is what the file
// is for the purposes of a relay that cannot forward any of them.
const HEIF_BRANDS: Record<string, true> = {
  heic: true,
  heix: true,
  hevc: true,
  hevx: true,
  heim: true,
  heis: true,
  hevm: true,
  hevs: true,
  mif1: true,
  msf1: true,
}

/**
 * The canonical MIME type of the image in `bytes`, or null when the leading
 * bytes match no known image format. A truncated file returns null rather
 * than throwing: an empty or partial upload is a rejection, not a crash.
 */
export function sniffImageFormat(bytes: Uint8Array): string | null {
  if (startsWith(bytes, PNG_SIGNATURE)) return 'image/png'
  if (GIF_SIGNATURES.some((signature) => startsWith(bytes, signature))) return 'image/gif'
  if (startsWith(bytes, BMP_SIGNATURE)) return 'image/bmp'
  if (TIFF_SIGNATURES.some((signature) => startsWith(bytes, signature))) return 'image/tiff'
  if (startsWith(bytes, JPEG_SIGNATURE)) return 'image/jpeg'
  // RIFF at 0 and 'WEBP' at 8; the four bytes between are the RIFF chunk size.
  if (bytes.length >= 12 && asciiAt(bytes, 0, 4) === 'RIFF' && asciiAt(bytes, 8, 4) === 'WEBP') {
    return 'image/webp'
  }
  // ISO base media file format: box size, 'ftyp' at 4, major brand at 8. The
  // brand check keeps a QuickTime or AVIF file — same container — from being
  // read as HEIC.
  if (
    bytes.length >= 12 &&
    asciiAt(bytes, 4, 4) === 'ftyp' &&
    HEIF_BRANDS[asciiAt(bytes, 8, 4)] === true
  ) {
    return 'image/heic'
  }
  return null
}

function startsWith(bytes: Uint8Array, signature: readonly number[]): boolean {
  if (bytes.length < signature.length) return false
  for (let i = 0; i < signature.length; i++) {
    if (bytes[i] !== signature[i]) return false
  }
  return true
}

/** The ASCII text of `length` bytes at `offset`; only meaningful for bytes < 0x80. */
function asciiAt(bytes: Uint8Array, offset: number, length: number): string {
  let out = ''
  for (let i = offset; i < offset + length; i++) out += String.fromCharCode(bytes[i])
  return out
}
