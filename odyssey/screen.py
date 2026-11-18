"""pygame-ce window that shows the emulated Apple II screen and plays its speaker."""
import array
import os
import time

os.environ.setdefault('PYGAME_HIDE_SUPPORT_PROMPT', '1')
import pygame  # noqa: E402

from .apple import RealTime, Quit, TEXT1, TEXT2, TEXT_ROW  # noqa: E402
from .hires import HEIGHT, WIDTH  # noqa: E402

HIRES_PALETTE = [(0, 0, 0), (255, 255, 255), (255, 68, 253), (20, 245, 60),
                 (20, 207, 253), (255, 106, 60)]
LORES_PALETTE = [(0, 0, 0), (227, 30, 96), (96, 78, 189), (255, 68, 253),
                 (0, 163, 96), (156, 156, 156), (20, 207, 253), (208, 195, 255),
                 (96, 114, 3), (255, 106, 60), (156, 156, 156), (255, 160, 208),
                 (20, 245, 60), (208, 221, 141), (114, 255, 208), (255, 255, 255)]
TEXT_FG = (255, 255, 255)

# 5x7 glyphs for character codes $20-$5F (codes $00-$1F reuse $40-$5F).
FONT = {
    ' ': '00 00 00 00 00 00 00', '!': '04 04 04 04 04 00 04', '"': '0A 0A 0A 00 00 00 00',
    '#': '0A 0A 1F 0A 1F 0A 0A', '$': '04 0F 14 0E 05 1E 04', '%': '18 19 02 04 08 13 03',
    '&': '08 14 14 08 15 12 0D', "'": '04 04 04 00 00 00 00', '(': '04 08 10 10 10 08 04',
    ')': '04 02 01 01 01 02 04', '*': '04 15 0E 04 0E 15 04', '+': '00 04 04 1F 04 04 00',
    ',': '00 00 00 00 04 04 08', '-': '00 00 00 1F 00 00 00', '.': '00 00 00 00 00 00 04',
    '/': '00 01 02 04 08 10 00', '0': '0E 11 13 15 19 11 0E', '1': '04 0C 04 04 04 04 0E',
    '2': '0E 11 01 06 08 10 1F', '3': '1F 01 02 06 01 11 0E', '4': '02 06 0A 12 1F 02 02',
    '5': '1F 10 1E 01 01 11 0E', '6': '07 08 10 1E 11 11 0E', '7': '1F 01 02 04 08 08 08',
    '8': '0E 11 11 0E 11 11 0E', '9': '0E 11 11 0F 01 02 1C', ':': '00 00 04 00 04 00 00',
    ';': '00 00 04 00 04 04 08', '<': '02 04 08 10 08 04 02', '=': '00 00 1F 00 1F 00 00',
    '>': '08 04 02 01 02 04 08', '?': '0E 11 02 04 04 00 04', '@': '0E 11 15 17 16 10 0F',
    'A': '04 0A 11 11 1F 11 11', 'B': '1E 11 11 1E 11 11 1E', 'C': '0E 11 10 10 10 11 0E',
    'D': '1E 11 11 11 11 11 1E', 'E': '1F 10 10 1E 10 10 1F', 'F': '1F 10 10 1E 10 10 10',
    'G': '0F 10 10 13 11 11 0F', 'H': '11 11 11 1F 11 11 11', 'I': '0E 04 04 04 04 04 0E',
    'J': '01 01 01 01 01 11 0E', 'K': '11 12 14 18 14 12 11', 'L': '10 10 10 10 10 10 1F',
    'M': '11 1B 15 15 11 11 11', 'N': '11 11 19 15 13 11 11', 'O': '0E 11 11 11 11 11 0E',
    'P': '1E 11 11 1E 10 10 10', 'Q': '0E 11 11 11 15 12 0D', 'R': '1E 11 11 1E 14 12 11',
    'S': '0E 11 10 0E 01 11 0E', 'T': '1F 04 04 04 04 04 04', 'U': '11 11 11 11 11 11 0E',
    'V': '11 11 11 11 11 0A 04', 'W': '11 11 11 15 15 1B 11', 'X': '11 11 0A 04 0A 11 11',
    'Y': '11 11 0A 04 04 04 04', 'Z': '1F 01 02 04 08 10 1F', '[': '1F 18 18 18 18 18 1F',
    '\\': '00 10 08 04 02 01 00', ']': '1F 03 03 03 03 03 1F', '^': '00 00 04 0A 11 00 00',
    '_': '00 00 00 00 00 00 1F',
}

KEYMAP = {
    pygame.K_RETURN: 0x0D, pygame.K_KP_ENTER: 0x0D, pygame.K_ESCAPE: 0x1B,
    pygame.K_BACKSPACE: 0x08, pygame.K_LEFT: 0x08, pygame.K_RIGHT: 0x15,
    pygame.K_SPACE: 0x20,
}

RATE = 22050


class Window(RealTime):
    def __init__(self, scale=3, sound=True, title='Odyssey: The Compleat Apventure'):
        pygame.init()
        self.scale = scale
        self.win = pygame.display.set_mode((WIDTH * scale, HEIGHT * scale))
        pygame.display.set_caption(title)
        self.base = pygame.Surface((WIDTH, HEIGHT))
        self.hires_rgb = pygame.Surface((WIDTH, HEIGHT))
        self.glyphs = self._make_glyphs()
        self.last_frame = 0.0
        self.flash_on = True
        self.sound_ok = False
        if sound:
            try:
                pygame.mixer.init(RATE, -16, 1, 512)
                self.channel = pygame.mixer.Channel(0)
                self.sound_ok = True
            except pygame.error:
                pass
        self.speaker = 1
        self.pending = array.array('h')

    # --- drawing --------------------------------------------------------------------------
    def _make_glyphs(self):
        glyphs = {}
        for code in range(64):
            ch = chr(code if code >= 0x20 else code + 0x40)
            rows = [int(h, 16) for h in FONT.get(ch, FONT[' ']).split()]
            for inverse in (False, True):
                s = pygame.Surface((7, 8))
                s.fill(TEXT_FG if inverse else (0, 0, 0))
                fg = (0, 0, 0) if inverse else TEXT_FG
                for y, bits in enumerate(rows):
                    for x in range(5):
                        if bits & (0x10 >> x):
                            s.set_at((x + 1, y), fg)
                glyphs[code, inverse] = s
        return glyphs

    def _draw_text_rows(self, page, first, last):
        m = self.machine
        for r in range(first, last):
            a = page + TEXT_ROW[r]
            for c in range(40):
                b = m.ram[a + c]
                code = b & 0x3F
                if b >= 0x80:
                    inverse = False
                elif b >= 0x40:                  # flashing
                    inverse = self.flash_on
                else:
                    inverse = True
                self.base.blit(self.glyphs[code, inverse], (c * 7, r * 8))

    def _draw_lores(self, page, rows):
        m = self.machine
        for r in range(rows // 2):
            a = page + TEXT_ROW[r]
            for c in range(40):
                b = m.ram[a + c]
                self.base.fill(LORES_PALETTE[b & 15], (c * 7, r * 8, 7, 4))
                self.base.fill(LORES_PALETTE[b >> 4], (c * 7, r * 8 + 4, 7, 4))

    def _update_hires(self):
        h = self.machine.hires
        rows = h.dirty_rows
        if not rows:
            return
        h.dirty_rows = set()
        pa = pygame.PixelArray(self.hires_rgb)
        for y in rows:
            row = h.render_row(y, HIRES_PALETTE)
            for x in range(WIDTH):
                pa[x, y] = row[x]
        del pa

    def render(self):
        m = self.machine
        page = TEXT2 if m.page2 else TEXT1
        if m.text_mode:
            self._draw_text_rows(page, 0, 24)
        else:
            rows = 160 if m.mixed else 192
            if m.hires_mode:
                if m.page2:
                    self.base.fill((0, 0, 0), (0, 0, WIDTH, rows))
                else:
                    self._update_hires()
                    self.base.blit(self.hires_rgb, (0, 0), (0, 0, WIDTH, rows))
            else:
                self._draw_lores(page, 40 if m.mixed else 48)
            if m.mixed:
                self._draw_text_rows(page, 20, 24)
        pygame.transform.scale(self.base, self.win.get_size(), self.win)
        pygame.display.flip()

    # --- frontend interface --------------------------------------------------------------
    def poll(self):
        if self.sound_ok:
            self._feed()
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                raise Quit()
            if ev.type == pygame.KEYDOWN:
                code = KEYMAP.get(ev.key)
                if code is None and ev.unicode and ord(ev.unicode) < 128:
                    code = ord(ev.unicode.upper())
                if code is not None:
                    if ev.mod & pygame.KMOD_CTRL and 0x40 <= code < 0x60:
                        code -= 0x40
                    self.machine.key_pressed(code)
        now = time.monotonic()
        if now - self.last_frame >= 1 / 30:
            self.last_frame = now
            flash = int(now * 3.7) & 1 == 0
            if flash != self.flash_on:
                self.flash_on = flash
            self.render()

    def _play(self, samples):
        if self.sound_ok:
            self.pending.extend(samples)
            self._feed()

    def _feed(self):
        """Stream the speaker: keep one sound playing and one queued behind it."""
        if not self.pending or self.channel.get_queue() is not None:
            return
        snd = pygame.mixer.Sound(buffer=self.pending.tobytes())
        self.pending = array.array('h')
        if self.channel.get_busy():
            self.channel.queue(snd)
        else:
            self.channel.play(snd)

    def tone(self, half_period, count):
        per = max(1, round(half_period * RATE))
        samples = array.array('h')
        level = self.speaker
        for _ in range(count):
            level = -level
            samples.extend([level * 6000] * per)
        self.speaker = level
        self._play(samples)

    def clicks(self, n, spacing):
        per = max(1, round(spacing * RATE))
        samples = array.array('h')
        level = self.speaker
        for _ in range(n):
            level = -level
            samples.extend([level * 6000] * per)
        self.speaker = level
        self._play(samples)
