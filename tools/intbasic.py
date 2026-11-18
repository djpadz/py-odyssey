"""Apple Integer BASIC detokenizer."""
import sys

TOK = [
    "HIMEM:", "<EOL>", "_ ", ":", "LOAD", "SAVE", "CON", "RUN",
    "RUN", "DEL", ",", "NEW", "CLR", "AUTO", ",", "MAN",
    "HIMEM:", "LOMEM:", "+", "-", "*", "/", "=", "#",
    ">=", ">", "<=", "<>", "<", "AND", "OR", "MOD",
    "^", "+", "(", ",", "THEN", "THEN", ",", ",",
    '"', '"', "(", "!", "!", "(", "PEEK", "RND",
    "SGN", "ABS", "PDL", "RNDX", "(", "+", "-", "NOT",
    "(", "=", "#", "LEN(", "ASC(", "SCRN(", ",", "(",
    "$", "$", "(", ",", ",", ";", ";", ";",
    ",", ",", ",", "TEXT", "GR", "CALL", "DIM", "DIM",
    "TAB", "END", "INPUT", "INPUT", "INPUT", "FOR", "=", "TO",
    "STEP", "NEXT", ",", "RETURN", "GOSUB", "REM", "LET", "GOTO",
    "IF", "PRINT", "PRINT", "PRINT", "POKE", ",", "COLOR=", "PLOT",
    ",", "HLIN", ",", "AT", "VLIN", ",", "AT", "VTAB",
    "=", "=", ")", ")", "LIST", ",", "LIST", "POP",
    "NODSP", "NODSP", "NOTRACE", "DSP", "DSP", "TRACE", "PR#", "IN#",
]


def ch(b):
    """A character inside a string or REM; control characters as {^X}."""
    c = b & 0x7F
    return '{^%s}' % chr(c + 64) if c < 32 else chr(c)


def detok(data):
    out = []
    p = 0
    while p < len(data):
        ln = data[p]
        if ln == 0:
            break
        line = data[p:p + ln]
        num = line[1] | line[2] << 8
        i = 3
        s = []
        while i < ln:
            b = line[i]
            if b == 0x01:
                break
            if b >= 0x80:
                if 0xB0 <= b <= 0xB9:
                    v = line[i + 1] | line[i + 2] << 8
                    s.append(str(v))
                    i += 3
                    continue
                # identifier
                while i < ln and line[i] >= 0x80:
                    s.append(chr(line[i] & 0x7F))
                    i += 1
                continue
            if b == 0x28:  # string
                s.append('"')
                i += 1
                while line[i] != 0x29:
                    s.append(ch(line[i]))
                    i += 1
                s.append('"')
                i += 1
                continue
            if b == 0x5D:  # REM
                s.append(' REM ')
                i += 1
                while line[i] != 0x01:
                    s.append(ch(line[i]))
                    i += 1
                continue
            t = TOK[b]
            if t[0].isalpha():
                if s and not s[-1].endswith(' '):
                    s.append(' ')
                s.append(t + ' ')
            else:
                s.append(t)
            i += 1
        out.append(f"{num} " + ''.join(s).strip())
        p += ln
    return '\n'.join(out)


if __name__ == '__main__':
    print(detok(open(sys.argv[1], 'rb').read()))
