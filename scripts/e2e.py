#!/usr/bin/env python3
"""End-to-end walkthrough against a deployed PAWS backend, plus a deck seeder.

Two modes, one file:

  --seed N   publish N pets as the rescuer, so the deck is not empty for whoever
             tries the app by hand. Needs only the rescuer's token.
  (default)  the whole path the acceptance criteria describe: publish, swipe,
             accept, chat over the real WebSocket, and read the history back.

It takes two JWTs read from files and nothing else: it never handles a password
and it creates no accounts. Get a token with

  read -rsp 'Contraseña: ' P; echo
  curl -s -X POST "$API/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"...\",\"password\":\"$P\"}" | jq -r .token > ~/.paws_tok_a; unset P

The chat step deliberately opens a second socket for the same user and drops the
first, which is the page reload that used to leave a user connected but invisible
to the hub. That makes this script the behavioural check for that fix.
"""

import argparse
import json
import struct
import sys
import time
import uuid
import zlib

import requests
import websocket

SANTIAGO = (-33.4489, -70.6693)

# Pets the seeder publishes, cycled if N is larger. Varied on the axes the deck
# is supposed to care about, so the seeded deck is worth looking at.
SEED_PETS = [
    ("Pelusa", "cat", "Siamés", 2, "low", (255, 189, 89), "Tranquila, ideal para departamento."),
    ("Rocco", "dog", "Quiltro", 4, "high", (120, 170, 235), "Necesita patio y caminatas largas."),
    ("Luna", "dog", "Labrador", 1, "high", (235, 120, 160), "Cachorra, buena con niños."),
    ("Tomás", "cat", "Mestizo", 6, "low", (140, 200, 150), "Adulto, sereno, ya esterilizado."),
    ("Nube", "dog", "Poodle", 3, "medium", (200, 150, 235), "Pequeña, buena con otros perros."),
    ("Simón", "cat", "Naranjo", 5, "medium", (240, 160, 110), "Cariñoso, requiere cuidados dentales."),
    ("Kira", "dog", "Pastor", 2, "high", (110, 190, 200), "Activa, con experiencia previa recomendada."),
    ("Mota", "cat", "Angora", 4, "low", (180, 180, 220), "Tímida, mejor en hogar sin niños pequeños."),
]


def png(width, height, rgb):
    """A solid-colour PNG, so a seeded deck shows cards instead of broken images."""
    row = bytes(rgb) * width
    raw = b"".join(b"\x00" + row for _ in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


class Run:
    """Collects step results so one failure does not hide the ones after it."""

    def __init__(self):
        self.failed = 0

    def ok(self, label, detail=""):
        print(f"  \033[32mPASA\033[0m  {label}" + (f"  ({detail})" if detail else ""))

    def fail(self, label, detail=""):
        self.failed += 1
        print(f"  \033[31mFALLA\033[0m {label}" + (f"  ({detail})" if detail else ""))

    def check(self, cond, label, detail=""):
        (self.ok if cond else self.fail)(label, detail)
        return cond


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def publish(api, token, spec, jitter=0.0):
    """Publish one pet. Returns (status, pet dict, raw text)."""
    name, kind, breed, age, energy, colour, desc = spec
    form = {
        "name": (None, name),
        "type": (None, kind),
        "breed": (None, breed),
        "age": (None, str(age)),
        "description": (None, desc),
        "latitude": (None, str(SANTIAGO[0] + jitter)),
        "longitude": (None, str(SANTIAGO[1] + jitter)),
        "address": (None, "Santiago, Chile"),
        "energy_level": (None, energy),
        "is_vaccinated": (None, "true"),
        "is_sterilized": (None, "true"),
        "good_with_kids": (None, "true" if energy != "high" else "false"),
        "requires_yard": (None, "true" if kind == "dog" and energy == "high" else "false"),
        "images": (f"{name.lower()}.png", png(600, 400, colour), "image/png"),
    }
    resp = requests.post(f"{api}/pets", headers=auth(token), files=form, timeout=90)
    body = resp.json() if resp.ok else {}
    return resp.status_code, (body.get("pet", body) or {}), resp.text


def image_url(pet):
    images = pet.get("images") or pet.get("Images") or []
    return (images[0].get("url") or images[0].get("URL")) if images else None


def seed(api, token, count, r):
    print(f"\n== Sembrando {count} mascotas ==")
    for i in range(count):
        spec = SEED_PETS[i % len(SEED_PETS)]
        suffix = "" if i < len(SEED_PETS) else f" {i // len(SEED_PETS) + 1}"
        named = (spec[0] + suffix,) + spec[1:]
        status, pet, text = publish(api, token, named, jitter=(i % 5) * 0.01)
        pet_id = pet.get("id") or pet.get("ID")
        r.check(status in (200, 201) and pet_id, f"{named[0]}", f"{status}, id={pet_id}, {image_url(pet) or text[:60]}")
    return 1 if r.failed else 0


def walkthrough(args, tok_a, tok_b, r):
    api = args.api
    pet_id = None

    print("\n== 1. Las dos sesiones responden ==")
    runs = {}
    for name, tok in (("A/rescatista", tok_a), ("B/adoptante", tok_b)):
        resp = requests.get(f"{api}/profile", headers=auth(tok), timeout=30)
        user = (resp.json() if resp.ok else {}) or {}
        user = user.get("user", user) or {}
        runs[name] = user.get("run")
        r.check(resp.status_code == 200, f"{name} GET /profile", f"{resp.status_code}, id={user.get('id')}")

    if runs["A/rescatista"] and runs["A/rescatista"] == runs["B/adoptante"]:
        r.fail("las dos cuentas comparten RUN", "el mazo filtra por RUN: B nunca verá la mascota de A")

    print("\n== 2. A publica una mascota con foto ==")
    tag = uuid.uuid4().hex[:8]
    spec = (f"E2E {tag}", "dog", "Mestizo", 3, "medium", (230, 30, 110), "Mascota de prueba del arnés E2E.")
    status, pet, text = publish(api, tok_a, spec)
    pet_id = pet.get("id") or pet.get("ID")
    r.check(status in (200, 201) and pet_id, "POST /pets", f"{status}, id={pet_id}")

    url = image_url(pet)
    if r.check(bool(url), "la mascota trae imagen", url or text[:120]):
        r.check("cloudinary" in url.lower(), "la imagen se sirve desde Cloudinary", url)
        r.check(requests.head(url, timeout=30).status_code == 200, "la imagen responde 200")

    if not pet_id:
        return cleanup(r, api, tok_a, None, args.keep)

    print("\n== 3. La mascota aparece en el mazo de B ==")
    resp = requests.get(
        f"{api}/matches/candidates", headers=auth(tok_b),
        params={"lat": SANTIAGO[0], "lon": SANTIAGO[1]}, timeout=30,
    )
    deck = resp.json() if resp.ok else []
    deck = deck if isinstance(deck, list) else deck.get("pets", [])
    r.check(resp.status_code == 200, "GET /matches/candidates", str(resp.status_code))
    r.check(
        any((p.get("id") or p.get("ID")) == pet_id for p in deck),
        "la mascota recién publicada está en el mazo", f"{len(deck)} candidatas",
    )

    print("\n== 4. B desliza a la derecha y A ve la solicitud ==")
    resp = requests.post(f"{api}/matches/swipe", headers=auth(tok_b),
                         json={"pet_id": pet_id, "is_like": True}, timeout=30)
    r.check(resp.status_code in (200, 201), "POST /matches/swipe", str(resp.status_code))

    resp = requests.get(f"{api}/matches/requests", headers=auth(tok_a), timeout=30)
    pend = resp.json() if resp.ok else []
    pend = pend if isinstance(pend, list) else pend.get("matches", [])
    mine = [m for m in pend if (m.get("pet_id") or m.get("PetID")) == pet_id]
    match_id = (mine[0].get("id") or mine[0].get("ID")) if mine else None
    r.check(bool(match_id), "A ve la solicitud pendiente", f"match={match_id}, {len(pend)} pendientes")
    if not match_id:
        return cleanup(r, api, tok_a, pet_id, args.keep)

    print("\n== 5. A acepta ==")
    resp = requests.post(f"{api}/matches/respond", headers=auth(tok_a),
                         json={"match_id": match_id, "accept": True}, timeout=30)
    r.check(resp.status_code == 200, "POST /matches/respond", str(resp.status_code))

    print("\n== 6. Chat en tiempo real, con una recarga de por medio ==")
    text = f"mensaje del arnés {tag}"
    ws_a2 = ws_b = None
    try:
        # First socket for A, then a second one: this is the page reload. The first
        # is dropped, and its late unregister must not evict the live one.
        ws_a1 = websocket.create_connection(args.ws, subprotocols=["bearer", tok_a], timeout=20)
        ws_a2 = websocket.create_connection(args.ws, subprotocols=["bearer", tok_a], timeout=20)
        ws_a1.close()
        time.sleep(2)  # let the stale unregister reach the hub before measuring

        ws_b = websocket.create_connection(args.ws, subprotocols=["bearer", tok_b], timeout=20)
        ws_b.send(json.dumps({"match_id": match_id, "content": text}))

        ws_a2.settimeout(15)
        got = False
        deadline = time.time() + 15
        while time.time() < deadline and not got:
            try:
                frame = json.loads(ws_a2.recv())
            except websocket.WebSocketTimeoutException:
                break
            got = text in json.dumps(frame.get("payload") or {})
        r.check(got, "el mensaje llega en vivo al socket que sobrevivió a la recarga",
                "sin el arreglo del hub, no llega")
    except Exception as exc:  # noqa: BLE001 - the failure itself is the result
        r.fail("el chat por WebSocket", f"{type(exc).__name__}: {exc}")
    finally:
        for sock in (ws_a2, ws_b):
            try:
                sock and sock.close()
            except Exception:
                pass

    print("\n== 7. El historial persiste (lo que vería una recarga) ==")
    for name, tok in (("A", tok_a), ("B", tok_b)):
        resp = requests.get(f"{api}/matches/{match_id}/messages", headers=auth(tok), timeout=30)
        body = resp.json() if resp.ok else []
        body = body if isinstance(body, list) else body.get("messages", [])
        r.check(resp.status_code == 200 and any(text in json.dumps(m) for m in body),
                f"{name} recupera el mensaje por HTTP", f"{resp.status_code}, {len(body)} mensajes")

    return cleanup(r, api, tok_a, pet_id, args.keep)


def cleanup(r, api, tok_a, pet_id, keep):
    if pet_id and not keep:
        print("\n== 8. Limpieza ==")
        resp = requests.delete(f"{api}/pets/{pet_id}", headers=auth(tok_a), timeout=30)
        r.check(resp.status_code in (200, 204), "DELETE /pets/{id}", str(resp.status_code))
    return 1 if r.failed else 0


def main():
    ap = argparse.ArgumentParser(description="Recorrido E2E y sembrador del mazo de PAWS.")
    ap.add_argument("--api", default="https://paws-backend-m2g2.onrender.com/api/v1")
    ap.add_argument("--ws", default="wss://paws-backend-m2g2.onrender.com/api/v1/ws")
    ap.add_argument("--token-a", required=True, help="archivo con el JWT del rescatista")
    ap.add_argument("--token-b", help="archivo con el JWT del adoptante (no se usa con --seed)")
    ap.add_argument("--seed", type=int, metavar="N", help="publica N mascotas y termina")
    ap.add_argument("--keep", action="store_true", help="no borrar la mascota al terminar")
    args = ap.parse_args()
    args.api = args.api.rstrip("/")

    tok_a = open(args.token_a).read().strip()
    r = Run()

    if args.seed:
        code = seed(args.api, tok_a, args.seed, r)
    else:
        if not args.token_b:
            ap.error("el recorrido necesita --token-b (o usa --seed para solo sembrar)")
        code = walkthrough(args, tok_a, open(args.token_b).read().strip(), r)

    print("\n" + (f"\033[31m{r.failed} comprobaciones fallaron\033[0m" if r.failed else "\033[32mtodo verde\033[0m"))
    return code


if __name__ == "__main__":
    sys.exit(main())
