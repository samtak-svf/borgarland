// The magic-byte sniffer that backs the relay's photo validation.
//
// These are unit tests of the signatures themselves, using real bytes, because
// the cost of a wrong signature is asymmetric: a signature that is too
// generous (accepting something that is not that format) only shifts a failure
// to the city, while a signature that is too strict rejects a valid photo from
// a real phone — which is worse than the bug the sniffer fixes. Every accepted
// signature below is checked against the format's specification, and the
// truncated-input cases exist because a partial upload must be a clean
// rejection, never a crash.

import { describe, expect, it } from 'vitest'
import { sniffImageFormat } from '../src/image-format'

/** Builds bytes from a hex string with a space between octets. */
function bytes(hex: string): Uint8Array {
  return new Uint8Array(hex.split(' ').map((octet) => parseInt(octet, 16)))
}

describe('sniffImageFormat', () => {
  it('recognizes a JPEG by its FF D8 FF marker', () => {
    // SOI, APP0, and the JFIF identifier that follow it.
    expect(sniffImageFormat(bytes('FF D8 FF E0 00 10 4A 46 49 46 00 01'))).toBe('image/jpeg')
  })

  it('recognizes a PNG by its full eight-byte signature', () => {
    // The signature plus the start of the IHDR chunk.
    expect(sniffImageFormat(bytes('89 50 4E 47 0D 0A 1A 0A 00 00 00 0D 49 48 44 52'))).toBe(
      'image/png',
    )
  })

  it('recognizes both GIF versions', () => {
    expect(sniffImageFormat(bytes('47 49 46 38 37 61 01 00'))).toBe('image/gif') // GIF87a
    expect(sniffImageFormat(bytes('47 49 46 38 39 61 01 00'))).toBe('image/gif') // GIF89a
  })

  it('recognizes a BMP by its BM marker', () => {
    expect(sniffImageFormat(bytes('42 4D 36 00 00 00'))).toBe('image/bmp')
  })

  it('recognizes a TIFF in either byte order', () => {
    expect(sniffImageFormat(bytes('49 49 2A 00 08 00 00 00'))).toBe('image/tiff') // 'II*\0'
    expect(sniffImageFormat(bytes('4D 4D 00 2A 00 00 00 08'))).toBe('image/tiff') // 'MM\0*'
  })

  it('recognizes a WebP by its RIFF and WEBP markers', () => {
    // 'RIFF', a chunk size, 'WEBP'.
    expect(sniffImageFormat(bytes('52 49 46 46 24 00 00 00 57 45 42 50'))).toBe('image/webp')
  })

  it('recognizes HEIC by its ftyp box and major brand', () => {
    // The case the sniffer exists for: an iPhone's HEIC. Box size, 'ftyp',
    // major brand 'heic'.
    expect(sniffImageFormat(bytes('00 00 00 18 66 74 79 70 68 65 69 63'))).toBe('image/heic')
  })

  it('recognizes the other HEIF brands as HEIC', () => {
    // 'heix' is the 10-bit profile an iPhone writes for HDR; 'mif1' is the
    // generic HEIF container. A brand outside the set is a different file.
    expect(sniffImageFormat(bytes('00 00 00 18 66 74 79 70 68 65 69 78'))).toBe('image/heic')
    expect(sniffImageFormat(bytes('00 00 00 18 66 74 79 70 6D 69 66 31'))).toBe('image/heic')
  })

  it('returns null for an ISO media file that is not HEIF', () => {
    // QuickTime's container is the same ftyp shape; only the brand differs.
    // Declaring a video as a photo is a rejection, not a HEIC misread.
    expect(sniffImageFormat(bytes('00 00 00 18 66 74 79 70 71 74 20 20'))).toBeNull()
  })

  it('returns null for a RIFF file that is not a WebP', () => {
    // A WAV has the same RIFF wrapper; the WEBP marker at 8 is the discriminator.
    expect(sniffImageFormat(bytes('52 49 46 46 24 00 00 00 57 41 56 45'))).toBeNull()
  })

  it('returns null for unrecognised bytes', () => {
    expect(sniffImageFormat(bytes('00 01 02 03 04 05 06 07'))).toBeNull()
  })

  it('returns null for an empty file', () => {
    expect(sniffImageFormat(new Uint8Array(0))).toBeNull()
  })

  it('returns null for a truncated signature instead of throwing', () => {
    // A JPEG cut to its first two bytes, and a PNG cut to seven of its eight.
    expect(sniffImageFormat(bytes('FF D8'))).toBeNull()
    expect(sniffImageFormat(bytes('89 50 4E 47 0D 0A 1A'))).toBeNull()
  })
})
