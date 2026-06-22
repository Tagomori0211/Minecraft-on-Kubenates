#!/usr/bin/env python3
"""
bedrock-leveldat-fix.py — BDS level.dat (Bedrock, little-endian NBT) の外科的パッチツール

経緯: 2026-06-21 のインシデント（Bedrock 接続タイムアウト）。
  真因は world「Bedrock level」の level.dat で `LANBroadcast=0` / `MultiplayerGameIntent=0`
  だったこと。これにより BDS が offline-ping(UNCONNECTED_PONG) に server-ID文字列(MOTD)を
  載せず、クライアントがサーバ情報を取得できず接続不能になっていた。
  → これら2フラグを 1 にするだけで、他フィールド（スポーン/シード/エンティティ参照等）を
    完全保持したまま復旧できる（= world 新規初期化「CREATING」を避け「LOADING」させる）。
  詳細: Documents/OperationPostmortem/postmortem-bedrock-motd-unjoinable.md

使い方:
  1) 対象 level.dat を取り出す（必ず実ワールドの複製に対して作業すること）:
       kubectl exec <pod> -c bedrock -- sh -c 'base64 "/data/worlds/<W>/level.dat"' | base64 -d > level.dat
  2) パッチ:  python3 bedrock-leveldat-fix.py level.dat level.dat.fixed
  3) 複製 world の level.dat を差し替えて起動 → 起動ログが「LOADING VANILLA WORLD」かつ
     pong に MOTD(MCPE;...) が載ることを確認してから本採用。
  --dump で中身ダンプのみ。

注意: round-trip 一致を内部で検証する。一致しない場合は中断（壊さないため）。
"""
import struct, sys

class R:
    def __init__(s, b): s.b = b; s.p = 0
    def rd(s, n): x = s.b[s.p:s.p+n]; s.p += n; return x

def r_str(r): l = struct.unpack('<H', r.rd(2))[0]; return r.rd(l).decode('utf-8', 'surrogatepass')
def w_str(x): e = x.encode('utf-8', 'surrogatepass'); return struct.pack('<H', len(e)) + e

def r_pay(r, t):
    if t == 1:  return ('b',  struct.unpack('<b', r.rd(1))[0])
    if t == 2:  return ('s',  struct.unpack('<h', r.rd(2))[0])
    if t == 3:  return ('i',  struct.unpack('<i', r.rd(4))[0])
    if t == 4:  return ('l',  struct.unpack('<q', r.rd(8))[0])
    if t == 5:  return ('f',  struct.unpack('<f', r.rd(4))[0])
    if t == 6:  return ('d',  struct.unpack('<d', r.rd(8))[0])
    if t == 7:  n = struct.unpack('<i', r.rd(4))[0]; return ('ba', list(r.rd(n)))
    if t == 8:  return ('str', r_str(r))
    if t == 9:  it = r.rd(1)[0]; n = struct.unpack('<i', r.rd(4))[0]; return ('list', (it, [r_pay(r, it) for _ in range(n)]))
    if t == 10:
        items = []
        while True:
            tt = r.rd(1)[0]
            if tt == 0: break
            nm = r_str(r); items.append((nm, tt, r_pay(r, tt)))
        return ('comp', items)
    if t == 11: n = struct.unpack('<i', r.rd(4))[0]; return ('ia', [struct.unpack('<i', r.rd(4))[0] for _ in range(n)])
    if t == 12: n = struct.unpack('<i', r.rd(4))[0]; return ('la', [struct.unpack('<q', r.rd(8))[0] for _ in range(n)])
    raise ValueError(f'unknown tag {t}')

def w_pay(t, v):
    _, val = v
    if t == 1:  return struct.pack('<b', val)
    if t == 2:  return struct.pack('<h', val)
    if t == 3:  return struct.pack('<i', val)
    if t == 4:  return struct.pack('<q', val)
    if t == 5:  return struct.pack('<f', val)
    if t == 6:  return struct.pack('<d', val)
    if t == 7:  return struct.pack('<i', len(val)) + bytes(val)
    if t == 8:  return w_str(val)
    if t == 9:
        it, items = val; out = bytes([it]) + struct.pack('<i', len(items))
        for x in items: out += w_pay(it, x)
        return out
    if t == 10:
        out = b''
        for nm, tt, pv in val: out += bytes([tt]) + w_str(nm) + w_pay(tt, pv)
        return out + b'\x00'
    if t == 11: return struct.pack('<i', len(val)) + b''.join(struct.pack('<i', x) for x in val)
    if t == 12: return struct.pack('<i', len(val)) + b''.join(struct.pack('<q', x) for x in val)
    raise ValueError(f'unknown tag {t}')

# 接続広告に必要なフラグ（byte tag）。0 だと MOTD が載らない。
FIX_FLAGS = {'LANBroadcast': 1, 'LANBroadcastIntent': 1, 'MultiplayerGame': 1, 'MultiplayerGameIntent': 1}

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    src = sys.argv[1]
    d = open(src, 'rb').read()
    ver, ln = struct.unpack('<ii', d[:8]); body = d[8:8+ln]
    r = R(body); top_t = r.rd(1)[0]; top_nm = r_str(r); top = r_pay(r, 10)

    # round-trip 検証（壊さない保証）
    rt = bytes([top_t]) + w_str(top_nm) + w_pay(10, top)
    if rt != body:
        print('ERROR: round-trip 不一致。パーサがこの level.dat を完全再現できないため中断。'); sys.exit(2)

    _, items = top
    if '--dump' in sys.argv:
        for nm, tt, pv in items:
            print(f'{nm} (tag {tt}) = {str(pv[1])[:70]}')
        return

    changed = []
    for i, (nm, tt, pv) in enumerate(items):
        if nm in FIX_FLAGS and tt == 1 and pv[1] != FIX_FLAGS[nm]:
            items[i] = (nm, tt, ('b', FIX_FLAGS[nm])); changed.append(f'{nm}:{pv[1]}->{FIX_FLAGS[nm]}')
    new_body = bytes([top_t]) + w_str(top_nm) + w_pay(10, top)
    out = struct.pack('<ii', ver, len(new_body)) + new_body
    dst = sys.argv[2] if len(sys.argv) > 2 else src + '.fixed'
    open(dst, 'wb').write(out)
    print('changed:', changed or '(なし＝既に正常)')
    print(f'wrote {dst} ({len(out)} bytes, src {len(d)} bytes)')

if __name__ == '__main__':
    main()
