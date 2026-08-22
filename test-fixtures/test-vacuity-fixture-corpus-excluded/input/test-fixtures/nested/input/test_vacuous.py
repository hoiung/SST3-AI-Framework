"""Fixture member: an intentionally-vacuous known-answer corpus file that bare
discovery MUST NOT scan (#567 T3 E3 — the gate was red by default in its own
repo because discovery walked into its positive-control fixtures)."""


def test_intentionally_vacuous():
    assert True
