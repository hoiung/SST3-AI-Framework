"""Fixture: detector precision after #567 T3 S6a/S6b. Two truthy-container
findings; two always-FALSE self-compares that must NOT be claimed (they redden
the suite themselves — not a silent-pass hazard); one genuine negative. The
paired expected.json pins the sentinel at exactly 2 findings, so an over-eager
widening that reclaims the always-false forms drifts this fixture."""


def helper(x):
    return x + 1


def test_truthy_dict_literal():
    assert {"a": 1}  # assert-literal: non-empty dict is always true


def test_truthy_set_literal():
    assert {1, 2}  # assert-literal: non-empty set is always true


def test_always_false_neq_not_claimed():
    assert helper(1) != helper(1)  # always FAILS — suite reddens; NOT vacuous


def test_always_false_lt_not_claimed():
    assert helper(1) < helper(1)  # always FAILS — suite reddens; NOT vacuous


def test_genuine_assertion():
    # Negative control: a real assertion must NOT be flagged.
    assert helper(1) == 2
