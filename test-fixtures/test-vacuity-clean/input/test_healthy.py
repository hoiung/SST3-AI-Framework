"""Negative-control fixture: genuine assertions only — the sweep must exit 0
with zero findings (a gate that fails on everything is as broken as one that
passes on everything; mutation-verification.md)."""


def double(x):
    return x * 2


def test_double():
    assert double(3) == 6


def test_double_zero():
    expected = 0
    assert double(0) == expected
