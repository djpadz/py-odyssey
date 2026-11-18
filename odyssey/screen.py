"""pygame-ce window that shows the emulated Apple II screen and plays its speaker.

Two looks (F2 switches between them; --classic starts in the second):

  enhanced - the default.  The four hi-res pictures (title, island, sea chart,
             fortress) are replaced by repainted artwork (odyssey/assets/art,
             made by tools/render_art.py).  Whatever the game draws on top of a
             picture - the party, ships, monsters, site markers - is found by
             replaying its drawing on a black sprite layer (hires.py), and is
             drawn over the art as crisp square pixels.  Any other hi-res screen is
             smoothed with EPX.
             Text and lo-res graphics stay crisp.
  classic  - exactly the Apple's 280x192 pixels, scaled up.

Either way the picture fills the window at its full (Retina) resolution; the
window can be resized and F11 (or Alt/Cmd-Return) toggles full screen.
"""
import array
import os
import time

os.environ.setdefault('PYGAME_HIDE_SUPPORT_PROMPT', '1')
import pygame  # noqa: E402

from .apple import RealTime, Quit, TEXT1, TEXT2, TEXT_ROW  # noqa: E402
from .hires import HEIGHT, WIDTH, Hires  # noqa: E402

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

RATE = 44100
AMP = 6000


STYLES = ('enhanced', 'classic')
KEY = (1, 2, 3)                      # transparent colour of the overlay
ART_DIR = os.path.join(os.path.dirname(__file__), 'assets')


class Window(RealTime):
    def __init__(self, scale=3, sound=True, title='Odyssey: The Compleat Apventure', style='enhanced'):
        pygame.init()
        self.title = title
        self.style = style if style in STYLES else STYLES[0]
        self.window = pygame.Window(title, (WIDTH * scale, HEIGHT * scale),
                                    resizable=True, allow_high_dpi=True)
        self.window.minimum_size = (WIDTH, HEIGHT)
        self.surface = self.window.get_surface()
        self.fullscreen = False
        self._set_title()
        self.base = pygame.Surface((WIDTH, HEIGHT))
        self.hires_rgb = pygame.Surface((WIDTH, HEIGHT))
        self.overlay = pygame.Surface((WIDTH, HEIGHT))
        self.overlay.set_colorkey(KEY)
        self.overlay_rows = [0] * HEIGHT       # pixels in each row that differ from the picture
        self.overlay_picture = None
        self.baselines = {}                    # picture name -> original rows
        self.art = {}                          # picture name -> art Surface (or None)
        self.art_scaled = {}                   # (name, size) -> scaled art
        self.glyphs = self._make_glyphs()
        self.last_frame = 0.0
        self.flash_on = True
        self.shown = None             # what was last presented
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
        self.audio_now = 0.0          # emulated time
        self.audio_end = 0.0          # emulated time the written sound reaches
        self.audio_pos = 0.0          # fractional sample carried between writes

    @property
    def win(self):
        return self.surface

    def _set_title(self):
        other = STYLES[1 - STYLES.index(self.style)]
        self.window.title = '%s   [%s - F2: %s, F11: full screen]' % (self.title, self.style, other)

    def _resized(self):
        self.surface = self.window.get_surface()
        self.shown = None

    def toggle_fullscreen(self):
        if self.fullscreen:
            self.window.set_windowed()
        else:
            self.window.set_fullscreen(desktop=True)
        self.fullscreen = not self.fullscreen
        self._resized()

    def next_style(self):
        self.style = STYLES[(STYLES.index(self.style) + 1) % len(STYLES)]
        self._set_title()
        self.shown = None

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

    def _baseline(self, name):
        """The original picture's colours, row by row."""
        rows = self.baselines.get(name)
        if rows is None:
            h = Hires()
            h.load(open(os.path.join(ART_DIR, name + '.hgr'), 'rb').read())
            rows = self.baselines[name] = [h.render_row(y, HIRES_PALETTE) for y in range(HEIGHT)]
        return rows

    def _update_hires(self):
        h = self.machine.hires
        if h.picture != self.overlay_picture:
            self.overlay_picture = h.picture
            h.dirty = True
        rows = h.dirty_rows
        if not rows:
            return
        h.dirty_rows = set()
        base = self._baseline(h.picture) if h.picture else None
        pa = pygame.PixelArray(self.hires_rgb)
        po = pygame.PixelArray(self.overlay)
        black = HIRES_PALETTE[0]
        for y in rows:
            row = h.render_row(y, HIRES_PALETTE)
            sprites = h.render_row(y, HIRES_PALETTE, h.layer)
            ref = base[y] if base else None
            n = 0
            for x in range(WIDTH):
                c = row[x]
                pa[x, y] = c
                if ref is None or c != ref[x]:
                    n += 1
                sc = sprites[x]
                po[x, y] = KEY if sc == black else sc
            self.overlay_rows[y] = n
        del pa, po

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
        self.present()

    # --- presentation ---------------------------------------------------------------------
    def _art(self, name, size):
        """The repainted picture `name`, scaled to `size`, or None."""
        if name not in self.art:
            path = os.path.join(ART_DIR, 'art', name + '.jpg')
            self.art[name] = pygame.image.load(path).convert() if os.path.exists(path) else None
        art = self.art[name]
        if art is None:
            return None
        key = (name, size)
        scaled = self.art_scaled.get(key)
        if scaled is None:
            self.art_scaled = {k: v for k, v in self.art_scaled.items() if k[1] == size}
            scaled = self.art_scaled[key] = pygame.transform.smoothscale(art, size)
        return scaled

    def present(self):
        """Scale the 280x192 picture to the window in the current style."""
        m = self.machine
        out = self.surface
        ow, oh = out.get_size()
        k = min(ow / WIDTH, oh / HEIGHT)
        dw, dh = max(1, int(WIDTH * k)), max(1, int(HEIGHT * k))
        key = (pygame.image.tobytes(self.base, 'RGB'), (ow, oh), self.style)
        if key == self.shown:
            return                                  # nothing changed on screen
        self.shown = key
        dx, dy = (ow - dw) // 2, (oh - dh) // 2
        out.fill((0, 0, 0))
        gfx = 0 if m.text_mode else (160 if m.mixed else 192)
        if self.style == 'classic' or gfx == 0 or not m.hires_mode or m.page2:
            out.blit(pygame.transform.scale(self.base, (dw, dh)), (dx, dy))
        else:
            gh = round(dh * gfx / HEIGHT)
            shown_rows = self.overlay_rows[:gfx]
            art = None
            if m.hires.picture and sum(shown_rows) < 0.35 * WIDTH * gfx:
                art = self._art(m.hires.picture, (dw, dh))
            if art is not None:
                out.blit(art, (dx, dy), (0, 0, dw, gh))
                ov = pygame.transform.scale(self.overlay, (dw, dh))         # icons stay square
                ov.set_colorkey(KEY)
                out.blit(ov, (dx, dy), (0, 0, dw, gh))
            else:
                out.blit(self._smooth(dw, dh, k), (dx, dy), (0, 0, dw, gh))
            if gfx < HEIGHT:                         # the text window stays crisp
                text = self.base.subsurface((0, gfx, WIDTH, HEIGHT - gfx))
                out.blit(pygame.transform.scale(text, (dw, dh - gh)), (dx, dy + gh))
        self.window.flip()

    def _smooth(self, dw, dh, k):
        """EPX-smoothed hi-res, for pictures that have no repainted art."""
        big = pygame.transform.scale2x(pygame.transform.scale2x(self.base))
        if k > 6:
            big = pygame.transform.scale2x(big)
        return pygame.transform.smoothscale(big, (dw, dh))

    # --- frontend interface --------------------------------------------------------------
    def poll(self):
        if self.sound_ok:
            self._feed()
        for ev in pygame.event.get():
            if ev.type in (pygame.QUIT, pygame.WINDOWCLOSE):
                raise Quit()
            if ev.type in (pygame.WINDOWRESIZED, pygame.WINDOWSIZECHANGED,
                           pygame.WINDOWDISPLAYCHANGED, pygame.WINDOWEXPOSED):
                self._resized()
                continue
            if ev.type == pygame.KEYDOWN:
                if ev.key == pygame.K_F2:
                    self.next_style()
                    continue
                if ev.key == pygame.K_F11 or (ev.key == pygame.K_RETURN
                                              and ev.mod & (pygame.KMOD_ALT | pygame.KMOD_META)):
                    self.toggle_fullscreen()
                    continue
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

    # --- the speaker ------------------------------------------------------------------
    # Clicks are laid out on a timeline in emulated time: the game's waits move
    # the clock on, and the silence between two sounds is written out as such,
    # so the rhythm of an effect survives however the audio is buffered.
    def wait(self, seconds):
        self.audio_now += seconds
        super().wait(seconds)

    def clicks(self, intervals):
        if not self.sound_ok or not intervals:
            return
        gap = self.audio_now - self.audio_end
        if gap > 0.25:
            self.audio_end = self.audio_now           # a fresh sound starts now
        elif gap > 0:
            self._write(None, gap)                    # silence since the last one
        level = self.speaker
        for dt in intervals:
            level = -level                            # each click flips the cone
            self._write(level * AMP, dt)
        self.speaker = level
        self._feed()

    def _write(self, value, seconds):
        """Hold the output at `value` (None = silence) for `seconds`, keeping
        fractional samples so pitches stay exact."""
        end = self.audio_pos + seconds * RATE
        n = int(end) - int(self.audio_pos)
        self.audio_pos = end - int(end)
        self.pending.extend([value or 0] * n)
        self.audio_end += seconds

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
