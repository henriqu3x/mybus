#!/usr/bin/env python3
import json
import xml.etree.ElementTree as ET
import re
import sys
from pathlib import Path
from difflib import get_close_matches

ROOT = Path(__file__).resolve().parents[1]
KML_PATH = ROOT / 'assets' / 'paradas_onibus.kml'
LOGRAD_PATH = ROOT / 'assets' / 'logradouros_normalizados.json'
OUT_PATH = ROOT / 'assets' / 'logradouro_lookup_filled.json'

ACCENT_MAP = str.maketrans('áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
                           'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')

REMOVE_PREFIX_RE = re.compile(r"\b(rua|avenida|av\.|travessa|trav|rodovia|rod|estrada|est\.|praça|pca|pça|largo|alameda)\b", re.I)
NON_ALPHA = re.compile(r'[^a-z0-9\s]')


def normalize(s: str) -> str:
    s = s or ''
    s = s.translate(ACCENT_MAP)
    s = s.lower()
    s = REMOVE_PREFIX_RE.sub('', s)
    s = NON_ALPHA.sub(' ', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def extract_address_from_description(desc: str) -> str:
    # Heuristic: look for "Endereço" or similar markers
    if not desc:
        return ''
    m = re.search(r'End[aé]re[cç]o[:<\\/b>]*\s*([^<\\n]*)', desc, re.I)
    if m:
        return m.group(1).strip()
    # fallback: try to find any capitalized chunk that looks like a street
    return ''


def main():
    print('Loading logradouros...')
    lograd = json.loads(LOGRAD_PATH.read_text(encoding='utf-8'))
    # build maps
    normalized_to_id = {}
    names = []
    id_to_name = {}
    for e in lograd:
        name = e.get('nome') if isinstance(e, dict) else None
        idv = e.get('id') if isinstance(e, dict) else None
        if not name or not idv:
            continue
        norm = normalize(name)
        normalized_to_id[norm] = idv
        names.append(norm)
        id_to_name[idv] = name

    print(f'Loaded {len(id_to_name)} logradouros')

    print('Parsing paradas_onibus.kml...')
    tree = ET.parse(str(KML_PATH))
    root = tree.getroot()
    # KML often has namespace; find namespace
    ns = ''
    m = re.match(r'\{(.*)\}', root.tag)
    if m:
        ns = '{%s}' % m.group(1)

    placemarks = root.findall('.//' + ns + 'Placemark')
    print(f'Found {len(placemarks)} placemarks')

    lookup = {}  # api_id (int) -> list of stop ids (int)

    for pm in placemarks:
        # name element usually is stop id
        name_el = pm.find(ns + 'name')
        if name_el is None: continue
        stop_id_str = name_el.text.strip()
        try:
            stop_id = int(stop_id_str)
        except Exception:
            continue
        desc_el = pm.find(ns + 'description')
        desc = desc_el.text if desc_el is not None else ''
        addr = extract_address_from_description(desc)
        if not addr:
            # try to take the first line of description
            if desc:
                addr = desc.split('<br')[0].strip()[:200]
        norm = normalize(addr)
        if not norm:
            # try taking placemark's extended data or look for href
            continue

        # exact match
        api_id = normalized_to_id.get(norm)
        if api_id is None:
            # fuzzy match
            matches = get_close_matches(norm, names, n=3, cutoff=0.7)
            if matches:
                api_id = normalized_to_id.get(matches[0])
        if api_id is None:
            # try token intersection: find candidate with most shared tokens
            tokens = set(norm.split())
            best = None
            best_score = 0
            for cand in names:
                cand_tokens = set(cand.split())
                inter = tokens.intersection(cand_tokens)
                if not inter: continue
                score = len(inter)
                if score > best_score:
                    best_score = score
                    best = cand
            if best is not None:
                api_id = normalized_to_id.get(best)

        if api_id is None:
            # skip unknown
            continue

        lookup.setdefault(api_id, []).append(stop_id)

    # Sort and unique the lists
    for k,v in lookup.items():
        lookup[k] = sorted(list(set(v)))

    print(f'Generated mapping for {len(lookup)} logradouros')
    OUT_PATH.write_text(json.dumps(lookup, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Wrote {OUT_PATH}')


if __name__ == '__main__':
    main()
