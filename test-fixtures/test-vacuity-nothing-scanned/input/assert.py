"""A vacuous file OUTSIDE the bare-discovery glob (not under tests/, not
test_*.py) — the exact #567 Ralph T3 F2 probe: before the fix, bare-mode
discovery skipped it and the gate printed 'scanned 0 file(s), 0 finding(s)' at
exit 0, indistinguishable from ran-and-clean. The paired expected.json pins the
hardened contract: scanned == 0 is could-not-look, exit 2, never a clean PASS.
"""


def check():
    assert True
