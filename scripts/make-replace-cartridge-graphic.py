#!/usr/bin/env python3
"""Builds the replace_cartridge animation from Tandem's remove_cartridge.

The cartridge coming out (frames 0 to FORWARD_END), then the same frames backwards, so the new one
goes in the way the old one came out. The source's own ending, where the cartridge fades back into
place, is left out.

The frames are written here instead of with gifsicle or ImageMagick: both give each frame its own
transparent index, and a decoder that clears a disposed frame to the screen's background index then
leaves opaque specks where the cartridge was. Like the source, every frame here shares one
transparent index, which is also the background. Needs Pillow.
"""

import struct
import sys
from pathlib import Path

from PIL import GifImagePlugin, Image, ImageChops

# Keeps decoded frames as palette indices: mapping their RGB back onto the table is not exact in Pillow.
GifImagePlugin.LOADING_STRATEGY = GifImagePlugin.LoadingStrategy.RGB_AFTER_DIFFERENT_PALETTE_ONLY

FORWARD_END = 230
ASSETS = Path(__file__).resolve().parent.parent / "Sources/TandemKitUI/Media.xcassets/MobiAppGraphics"
KEEP, CLEAR_TO_BACKGROUND = 1, 2


def read_source(path):
    """The global colour table, transparent index, frame delay (ms) and every composited frame as indices."""
    header = path.read_bytes()[:13 + 768]
    packed = header[10]
    assert packed & 0x80, "source has no global colour table"
    table = header[13:13 + 3 * (2 << (packed & 7))]

    image = Image.open(path)
    transparent = image.info["transparency"]
    assert image.info["background"] == transparent, "source background is not its transparent index"
    delay = image.info["duration"]
    return table, transparent, delay, indexed_frames(image, delay)


def indexed_frames(image, delay):
    """One frame of palette indices per `delay` the image shows it for."""
    frames = []
    for index in range(image.n_frames):
        image.seek(index)
        assert image.mode == "P", "a frame has its own colour table"
        frame = Image.frombytes("L", image.size, image.tobytes())
        frames += [frame] * (image.info["duration"] // delay)
    return frames


def lzw(pixels, code_bits):
    clear, end = 1 << code_bits, (1 << code_bits) + 1
    out, bit_buffer, bit_count = bytearray(), 0, 0

    def emit(code, width):
        nonlocal bit_buffer, bit_count
        bit_buffer |= code << bit_count
        bit_count += width
        while bit_count >= 8:
            out.append(bit_buffer & 0xFF)
            bit_buffer >>= 8
            bit_count -= 8

    table, width, prefix = {}, code_bits + 1, None
    emit(clear, width)
    for pixel in pixels:
        if prefix is None:
            prefix = pixel
            continue
        key = (prefix, pixel)
        if key in table:
            prefix = table[key]
            continue
        emit(prefix, width)
        next_code = end + 1 + len(table)
        if next_code == 4096:
            emit(clear, width)
            table, width = {}, code_bits + 1
        else:
            table[key] = next_code
            if next_code == 1 << width:
                width += 1
        prefix = pixel
    emit(prefix, width)
    emit(end, width)
    if bit_count:
        out.append(bit_buffer & 0xFF)
    return bytes(out)


def sub_blocks(data):
    return b"".join(bytes([len(data[i:i + 255])]) + data[i:i + 255] for i in range(0, len(data), 255)) + b"\x00"


def encode(table, transparent, delay, frames):
    """Each frame holds only what changed. A frame followed by one that uncovers transparent pixels
    is disposed to the background over an area covering them, and the next redraws what was there."""
    size = frames[0].size
    code_bits = max(2, (len(table) // 3 - 1).bit_length())
    blank = Image.new("L", size, transparent)
    opaque = [frame.point(lambda value: 255 if value != transparent else 0) for frame in frames]

    records = []
    canvas = blank.copy()
    for index, frame in enumerate(frames):
        changed = ImageChops.difference(frame, canvas).point(lambda value: 255 if value else 0)
        # The frame after the last is the first: not every decoder clears the screen between loops.
        next_transparent = ImageChops.invert(opaque[(index + 1) % len(frames)])
        uncovered = ImageChops.multiply(opaque[index], next_transparent).getbbox()

        box = changed.getbbox()
        if box is None and uncovered is None and records:
            records[-1]["delay"] += delay
            continue

        boxes = [b for b in (box, uncovered) if b]
        if not boxes:
            boxes = [(0, 0, 1, 1)]
        box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
        content = Image.composite(frame, blank, changed).crop(box)
        disposal = CLEAR_TO_BACKGROUND if uncovered else KEEP
        records.append({"box": box, "pixels": content.tobytes(), "delay": delay, "disposal": disposal})

        canvas = frame.copy()
        if uncovered:
            canvas.paste(transparent, box)

    table_bits = (len(table) // 3 - 1).bit_length() - 1
    out = bytearray(b"GIF89a")
    out += struct.pack("<HHBBB", size[0], size[1], 0xF0 | table_bits, transparent, 0)
    out += table
    out += b"\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00"
    for record in records:
        left, top, right, bottom = record["box"]
        out += b"\x21\xF9\x04" + struct.pack("<BHB", record["disposal"] << 2 | 1, record["delay"] // 10, transparent) + b"\x00"
        out += b"\x2C" + struct.pack("<HHHHB", left, top, right - left, bottom - top, 0)
        out += bytes([code_bits]) + sub_blocks(lzw(record["pixels"], code_bits))
    out += b"\x3B"
    return bytes(out)


def verify(path, table, frames, delay):
    """Decoded again, the file shows at each step the frame meant for it."""
    assert path.read_bytes()[13:13 + len(table)] == table, f"{path.name}: colour table differs"
    decoded = indexed_frames(Image.open(path), delay)
    assert len(decoded) == len(frames), f"{path.name}: {len(decoded)} steps, expected {len(frames)}"
    for step, (got, expected) in enumerate(zip(decoded, frames)):
        assert got.tobytes() == expected.tobytes(), f"{path.name}: step {step} differs"


def main():
    for variant in ("lm", "dm"):
        for scale in ("2x", "3x"):
            source = f"{variant}_remove_cartridge@{scale}"
            name = f"{variant}_replace_cartridge@{scale}"
            table, transparent, delay, frames = read_source(ASSETS / f"{source}.dataset/{source}.gif")
            sequence = frames[:FORWARD_END + 1] + frames[FORWARD_END - 1:0:-1]

            dataset = ASSETS / f"{name}.dataset"
            dataset.mkdir(exist_ok=True)
            output = dataset / f"{name}.gif"
            output.write_bytes(encode(table, transparent, delay, sequence))
            contents = (ASSETS / f"{source}.dataset/Contents.json").read_text().replace(source, name)
            (dataset / "Contents.json").write_text(contents)
            verify(output, table, sequence, delay)
            print(f"{name}: {len(sequence)} steps, {output.stat().st_size} bytes")


if __name__ == "__main__":
    sys.exit(main())
