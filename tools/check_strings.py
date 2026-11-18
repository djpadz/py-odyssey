"""Check that every message string in a ported module appears verbatim in the original listing.

Usage: python3 tools/check_strings.py odyssey/island.py src_listings/ISLAND_APVENTURE.bas
"""
import ast, re, sys

def listing_strings(path):
    out = set()
    for line in open(path, encoding='latin-1'):
        for t in re.findall(r'"([^"]*)"', line):
            out.add(re.sub(r'\{\^(.)\}', lambda m: chr(ord(m.group(1)) - 64), t))
    return out

def code_strings(path):
    tree = ast.parse(open(path).read())
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef,)) and ast.get_docstring(node):
            node.body[0].value._doc = True
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str) and not getattr(node, '_doc', False):
            v = node.value
            if len(v) >= 4 and re.search(r'[A-Z]{2}', v) and not re.search(r'[a-z]', v):
                yield node.lineno, v

if __name__ == '__main__':
    have = listing_strings(sys.argv[2])
    bad = 0
    for ln, v in code_strings(sys.argv[1]):
        if v not in have:
            bad += 1
            # find closest by stripping spaces
            norm = lambda t: re.sub(r'[\x00-\x1f ]', '', t)
            key = norm(v)
            cands = [h for h in have if norm(h) == key]
            print(f'{ln}: {v!r}' + (f'\n      -> {cands[0]!r}' if cands else '   (NO MATCH)'))
    print(bad, 'mismatches')


def autofix(code_path, listing_path):
    """Replace near-miss strings (same text ignoring spaces/control chars) with the original."""
    src = open(code_path).read()
    have = listing_strings(listing_path)
    norm = lambda t: re.sub(r'[\x00-\x1f ]', '', t)
    index = {}
    for h in have:
        index.setdefault(norm(h), set()).add(h)
    tree = ast.parse(src)
    edits = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            v = node.value
            if v in have or len(v) < 4:
                continue
            c = index.get(norm(v))
            if c and len(c) == 1:
                seg = ast.get_source_segment(src, node)
                edits.append((node.lineno, node.col_offset, node.end_lineno, node.end_col_offset, repr(c.pop())))
    lines = src.splitlines(keepends=True)
    offs = [0]
    for l in lines:
        offs.append(offs[-1] + len(l))
    for l1, c1, l2, c2, new in sorted(edits, reverse=True):
        a = offs[l1 - 1] + len(lines[l1 - 1].encode()[:c1].decode())
        b = offs[l2 - 1] + len(lines[l2 - 1].encode()[:c2].decode())
        src = src[:a] + new + src[b:]
    open(code_path, 'w').write(src)
    print(len(edits), 'strings fixed')


if __name__ == '__main__' and len(sys.argv) > 3 and sys.argv[3] == '--fix':
    autofix(sys.argv[1], sys.argv[2])
