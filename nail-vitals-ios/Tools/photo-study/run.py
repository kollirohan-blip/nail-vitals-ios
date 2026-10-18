#!/usr/bin/env python3
"""Photo study: measure finger photos from any camera with the app's own code.

Photos live in captures/photo-study/<code>/<set>/ (see PHOTO-GUIDE.md); they are
gitignored and never leave the Mac. Each photo goes through Tools/photo-lab,
which compiles the app's Detection files, so the numbers are the app's numbers.

  python3 run.py            measure new photos, then print the summary
  python3 run.py --review   open the local review page (✓ or ✗ each automatic dot)

Only photos that pass the app's checks AND were approved on the review page
count, standing in for the app's "confirm the dot" step.
"""
import argparse, csv, html, http.server, json, math, os, re, statistics as st, subprocess, sys, urllib.parse, webbrowser

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
PHOTO_LAB = os.path.join(HERE, '..', 'photo-lab', 'photo-lab')
EXTS = ('.jpg', '.jpeg', '.heic', '.png')

# Published healthy values (PublishedNorms.swift): mean, SD.
BENTLEY_PROFILE = (168.3, 3.6)      # Bentley et al., Lancet 1976
HUSARIK_HYPONYCHIAL = (178.87, 4.70)  # Husarik et al., Swiss Med Wkly 2002


def photos(root):
    """(code, set, path) for every photo; photos directly in a code folder are set '1'."""
    out = []
    for code in sorted(os.listdir(root)):
        cdir = os.path.join(root, code)
        if code.startswith(('_', '.')) or not os.path.isdir(cdir):
            continue
        for name in sorted(os.listdir(cdir)):
            p = os.path.join(cdir, name)
            if os.path.isdir(p) and not name.startswith(('_', '.')):
                out += [(code, name, os.path.join(p, f)) for f in sorted(os.listdir(p)) if f.lower().endswith(EXTS)]
            elif name.lower().endswith(EXTS):
                out.append((code, '1', p))
    return out


def key_of(code, s, path):
    return f'{code}/{s}/{os.path.basename(path)}'


def measure(root, items):
    """Run photo-lab once per photo (cached by modification time); return {key: log text}."""
    out = os.path.join(root, '_out')
    os.makedirs(os.path.join(out, 'logs'), exist_ok=True)
    logs, new = {}, 0
    for code, s, path in items:
        stem = os.path.splitext(os.path.basename(path))[0]
        log = os.path.join(out, 'logs', f'{code}__{s}__{stem}.log')
        if not os.path.exists(log) or os.path.getmtime(log) < os.path.getmtime(path):
            ann = os.path.join(out, 'annotated', code, s)
            os.makedirs(ann, exist_ok=True)
            r = subprocess.run([PHOTO_LAB, path, '--out', ann], capture_output=True, text=True)
            open(log, 'w').write(r.stdout + r.stderr)
            new += 1
        logs[key_of(code, s, path)] = open(log).read()
    if new:
        print(f'measured {new} new photo(s)')
    return logs


def num(s):
    try:
        v = float(s)
        return None if math.isnan(v) else v
    except (TypeError, ValueError):
        return None


def parse(t):
    g = lambda pat: (lambda m: num(m.group(1)) if m else None)(re.search(pat, t))
    d = dict(sharp=g(r'sharpness ([\d.]+)'), de=g(r'contrast \(delta E\) ([\d.]+)'),
             blurry='-> blurry' in t, turned='hand clearly turned' in t)
    fl = re.search(r'flexion \(\+ = toward the palm\): DIP (-?[\d.]+)°\s+PIP (-?[\d.]+)°', t)
    d['dip'], d['pip'] = (num(fl.group(1)), num(fl.group(2))) if fl else (None, None)
    app = re.search(r'app: profile (no dip \(180\+\)|[\d.]+°)\s+hyponychial ([\w.]+)°\s+depth ratio ([\w.]+)', t)
    d['nodip'] = bool(app and app.group(1).startswith('no dip'))
    d['profile'] = (180.0 if d['nodip'] else num(app.group(1).rstrip('°'))) if app else None
    d['hyponychial'] = num(app.group(2)) if app else None
    d['ratio'] = num(app.group(3)) if app else None
    res = re.search(r'^\s*result: (.+?)(?:\s{2}\(.*)?$', t, re.M)
    d['result'] = res.group(1).strip() if res else ''
    nail = re.search(r'nail on the (\w+)', t)
    d['nail'] = nail.group(1) if nail else None
    raised = re.search(r'raised finger: (\w+)', t)
    d['raised'] = raised.group(1) if raised else None
    ann = re.search(r'^\s*annotated: (.+)$', t, re.M)
    d['annotated'] = ann.group(1).strip() if ann else None
    return d


def problems(d):
    """The app's checks (same thresholds as the study analysis): empty list = passes."""
    p = []
    if d['profile'] is None: p.append('no measurement')
    if d['blurry'] or (d['sharp'] is not None and d['sharp'] < 0.15): p.append('blurry')
    if d['turned']: p.append('hand turned')
    if d['de'] is not None and d['de'] < 24: p.append('background too close to skin colour')
    if d['raised'] not in ('index', None): p.append('not the index finger')
    if d['dip'] is not None and not -7.5 <= d['dip'] <= 2.5: p.append('finger bent (DIP)')
    if d['pip'] is not None and not -8 <= d['pip'] <= 9: p.append('finger bent (PIP)')
    return p


def verdict(m):
    over = sum([m['profile'] >= 176, (m['hyponychial'] or 0) >= 192, (m['ratio'] or 0) >= 1.0])
    near = sum([173 <= m['profile'] < 176, 189 <= (m['hyponychial'] or 0) < 192, 0.97 <= (m['ratio'] or 0) < 1.0])
    return 'worth discussing' if over >= 2 else ('measure again' if over == 1 or near >= 2 else 'typical')


def t95(df):
    table = {1: 12.71, 2: 4.30, 3: 3.18, 4: 2.78, 5: 2.57, 6: 2.45, 7: 2.36, 8: 2.31, 9: 2.26, 10: 2.23,
             12: 2.18, 15: 2.13, 20: 2.09, 25: 2.06, 30: 2.04}
    return table.get(df) or next((v for k, v in sorted(table.items()) if k >= df), 1.96)


def load_review(root):
    try:
        return json.load(open(os.path.join(root, 'review.json')))
    except (OSError, ValueError):
        return {}


def analyse(root, quiet=False):
    items = photos(root)
    if not items:
        print(f'No photos yet in {root}. See PHOTO-GUIDE.md.')
        return None
    logs = measure(root, items)
    review = load_review(root)
    rows = []
    for code, s, path in items:
        k = key_of(code, s, path)
        d = parse(logs[k])
        d.update(key=k, code=code, set=s, file=os.path.basename(path), problems=problems(d), review=review.get(k))
        d['counts'] = not d['problems'] and d['review'] is True
        rows.append(d)

    sets = []
    for (code, s) in sorted({(r['code'], r['set']) for r in rows}):
        good = [r for r in rows if r['code'] == code and r['set'] == s and r['counts']]
        if good:  # same finger as the set's first accepted photo (nail side)
            good = [r for r in good if r['nail'] == good[0]['nail']]
        if len(good) < 2:
            sets.append(dict(code=code, set=s, n=len(good), result=None))
            continue
        med = {f: st.median(r[f] for r in good if r[f] is not None) for f in ('profile', 'hyponychial', 'ratio')
               if any(r[f] is not None for r in good)}
        med.setdefault('hyponychial', None); med.setdefault('ratio', None)
        sets.append(dict(code=code, set=s, n=len(good), result=verdict(med), **{f: (round(v, 3) if v is not None else None) for f, v in med.items()}))

    done = [x for x in sets if x['result']]
    people = sorted({r['code'] for r in rows})
    by_person = {}
    for x in done:
        by_person.setdefault(x['code'], []).append(x)
    means = {c: st.mean(x['profile'] for x in v) for c, v in by_person.items()}
    summary = dict(people=len(people), photos=len(rows), measured=sum(r['profile'] is not None for r in rows),
                   passed_checks=sum(not r['problems'] for r in rows),
                   approved=sum(r['counts'] for r in rows),
                   awaiting_review=sum(1 for r in rows if not r['problems'] and r['review'] is None),
                   rejected_on_review=sum(1 for r in rows if not r['problems'] and r['review'] is False),
                   sets_with_result=len(done), people_with_result=len(by_person),
                   flags=sum(x['result'] == 'worth discussing' for x in done),
                   measure_again=sum(x['result'] == 'measure again' for x in done),
                   typical=sum(x['result'] == 'typical' for x in done))
    if done and summary['flags'] == 0:
        summary['false_flag_upper_95'] = round(3 / len(done), 3)  # rule of three
    if len(means) >= 2:
        v = list(means.values()); m, sd = st.mean(v), st.stdev(v); h = t95(len(v) - 1) * sd / math.sqrt(len(v))
        summary['person_mean_profile'] = dict(mean=round(m, 1), sd=round(sd, 1), ci95=[round(m - h, 1), round(m + h, 1)],
                                              n_people=len(v), published=BENTLEY_PROFILE)
    ss = df = 0
    for v in by_person.values():
        if len(v) >= 2:
            mu = st.mean(x['profile'] for x in v); ss += sum((x['profile'] - mu) ** 2 for x in v); df += len(v) - 1
    if df:
        summary['repeat_range_95'] = round(1.96 * math.sqrt(ss / df), 1)
        summary['repeat_people'] = sum(1 for v in by_person.values() if len(v) >= 2)

    out = os.path.join(root, '_out')
    cols = ['key', 'code', 'set', 'file', 'profile', 'nodip', 'hyponychial', 'ratio', 'result', 'sharp', 'de', 'dip', 'pip',
            'nail', 'raised', 'problems', 'review', 'counts']
    with open(os.path.join(out, 'photos.csv'), 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction='ignore'); w.writeheader()
        for r in rows: w.writerow({**r, 'problems': '; '.join(r['problems'])})
    with open(os.path.join(out, 'sets.csv'), 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=['code', 'set', 'n', 'profile', 'hyponychial', 'ratio', 'result'], extrasaction='ignore'); w.writeheader()
        for x in sets: w.writerow(x)
    json.dump(dict(summary=summary, sets=sets), open(os.path.join(out, 'summary.json'), 'w'), indent=1)

    if not quiet:
        print(f"\n{summary['people']} people · {summary['photos']} photos · {summary['measured']} measured · "
              f"{summary['passed_checks']} passed the checks · {summary['approved']} approved on review"
              f"{' · ' + str(summary['awaiting_review']) + ' waiting for review (run --review)' if summary['awaiting_review'] else ''}")
        print(f"{summary['sets_with_result']} sets with a result ({summary['people_with_result']} people): "
              f"{summary['typical']} typical, {summary['measure_again']} measure again, {summary['flags']} worth discussing")
        if 'false_flag_upper_95' in summary:
            print(f"no flags; rule of three: false-flag rate could still be up to {summary['false_flag_upper_95']:.0%} per set")
        if 'person_mean_profile' in summary:
            p = summary['person_mean_profile']
            print(f"person average profile {p['mean']}° (SD {p['sd']}, 95% CI {p['ci95'][0]}–{p['ci95'][1]}, n={p['n_people']}); "
                  f"published healthy {BENTLEY_PROFILE[0]} ± {BENTLEY_PROFILE[1]}")
        if 'repeat_range_95' in summary:
            print(f"repeat range ±{summary['repeat_range_95']}° ({summary['repeat_people']} people with 2+ sets)")
        bad = [r for r in rows if r['problems']]
        if bad:
            print('\nphotos that failed a check (retake these if you can):')
            for r in bad: print(f"  {r['key']}: {', '.join(r['problems'])}")
        print(f"\nfiles: {out}/photos.csv, sets.csv, summary.json")
    return rows


def serve_review(root):
    rows = analyse(root, quiet=True)
    if not rows:
        return
    out = os.path.realpath(os.path.join(root, '_out'))
    path_of = {r['key']: r['annotated'] for r in rows if r['annotated']}

    def page():
        review = load_review(root)
        cards = []
        for r in rows:
            if r['problems'] or not r['annotated']:
                continue
            k = html.escape(r['key'])
            state = {True: 'yes', False: 'no'}.get(review.get(r['key']), '')
            vals = f"{'no dip' if r['nodip'] else str(round(r['profile'], 1)) + '°'} · {r['hyponychial'] or '–'}° · {r['ratio'] or '–'}"
            cards.append(f'''<figure class="{state}" data-k="{k}"><a href="/img?k={urllib.parse.quote(r['key'])}" target="_blank">
<img loading="lazy" src="/thumb?k={urllib.parse.quote(r['key'])}" alt="{k}"></a>
<figcaption><b>{k}</b><br>{html.escape(vals)}<br><button data-v="1">✓ dot is right</button><button data-v="0">✗ wrong</button></figcaption></figure>''')
        n = len(cards)
        return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Photo study review</title><style>
:root {{ --bg:#F2F1EE; --card:#fff; --ink:#0E1626; --dim:#6B7686; --em:#047857; --red:#DC2626; --line:rgba(14,22,38,.1); }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#0B1220; --card:#141C2B; --ink:#F1F5F9; --dim:#94A3B8; --em:#34D399; --red:#F87171; --line:rgba(255,255,255,.1); }} }}
body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.45 -apple-system, sans-serif; }}
main {{ max-width:1200px; margin:0 auto; padding:24px 16px 60px; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(220px, 1fr)); gap:14px; margin-top:16px; }}
figure {{ margin:0; background:var(--card); border:2px solid var(--line); border-radius:14px; padding:8px; }}
figure.yes {{ border-color:var(--em); }} figure.no {{ border-color:var(--red); opacity:.6; }}
img {{ width:100%; aspect-ratio:9/16; object-fit:cover; border-radius:8px; background:var(--line); }}
figcaption {{ font-size:13px; color:var(--dim); margin-top:6px; }} figcaption b {{ color:var(--ink); }}
button {{ font:600 13px/1 inherit; margin:6px 6px 0 0; padding:8px 10px; border-radius:999px; border:1px solid var(--line); background:var(--bg); color:var(--ink); cursor:pointer; }}
</style></head><body><main><h1>Photo study review</h1>
<p>{n} photos passed the app's checks. For each one, zoom in (click the photo) and check the dot sits where the nail meets the skin, on the nail side. ✓ counts the photo; ✗ leaves it out. Your answers save as you click. When you're done, run <code>python3 run.py</code> again.</p>
<div class="grid">{''.join(cards)}</div></main><script>
document.querySelectorAll('figure button').forEach(b => b.addEventListener('click', async () => {{
  const f = b.closest('figure'), v = b.dataset.v === '1';
  const r = await fetch('/review', {{ method: 'POST', headers: {{ 'Content-Type': 'application/json' }}, body: JSON.stringify({{ k: f.dataset.k, v }}) }});
  if (r.ok) f.className = v ? 'yes' : 'no';
}}));
</script></body></html>'''

    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a): pass

        def do_GET(self):
            u = urllib.parse.urlparse(self.path)
            if u.path == '/':
                body = page().encode(); self.send_response(200); self.send_header('Content-Type', 'text/html; charset=utf-8')
            elif u.path in ('/img', '/thumb'):
                k = urllib.parse.parse_qs(u.query).get('k', [''])[0]
                p = os.path.realpath(path_of.get(k, ''))
                if not p.startswith(out + os.sep) or not os.path.exists(p):
                    self.send_error(404); return
                kind = 'image/png'
                if u.path == '/thumb':  # small JPEG preview, made once with macOS sips
                    th = os.path.join(out, 'thumbs', k.replace('/', '__') + '.jpg')
                    if not os.path.exists(th):
                        os.makedirs(os.path.dirname(th), exist_ok=True)
                        subprocess.run(['sips', '-Z', '900', '-s', 'format', 'jpeg', p, '--out', th], capture_output=True)
                    p, kind = (th, 'image/jpeg') if os.path.exists(th) else (p, kind)
                body = open(p, 'rb').read(); self.send_response(200); self.send_header('Content-Type', kind)
            else:
                self.send_error(404); return
            self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)

        def do_POST(self):
            if self.path != '/review':
                self.send_error(404); return
            d = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
            if d.get('k') not in path_of:
                self.send_error(400); return
            review = load_review(root); review[d['k']] = bool(d.get('v'))
            json.dump(review, open(os.path.join(root, 'review.json'), 'w'), indent=1)
            self.send_response(204); self.end_headers()

    srv = http.server.HTTPServer(('127.0.0.1', 8790), H)
    print('Review page: http://127.0.0.1:8790  (Ctrl-C to stop)')
    webbrowser.open('http://127.0.0.1:8790')
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', default=os.path.join(REPO, 'captures', 'photo-study'), help='photo folder (default: captures/photo-study)')
    ap.add_argument('--review', action='store_true', help='open the review page')
    a = ap.parse_args()
    if not os.path.exists(PHOTO_LAB):
        sys.exit('Build photo-lab first (see Tools/photo-lab/main.swift).')
    os.makedirs(a.root, exist_ok=True)
    serve_review(a.root) if a.review else analyse(a.root)
