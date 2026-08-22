"""Fixture: every AC 4.1 vacuous-assertion form, one per test. Frozen known-answer
input for sst3-test-vacuity.sh — the wrapper must exit 1 and emit >=5 findings."""


def helper(x):
    return x * 2


def test_assert_literal_true():
    assert True  # assert-literal: truthy constant


def test_assert_literal_string():
    assert "this bare continuation string is always truthy"  # assert-literal: string


def test_assert_tuple():
    assert (1 == 2, "classic tuple assert — always true")  # assert-literal: tuple


def test_assert_or_true():
    x = 5
    assert x == 99 or True  # assert-or-true


def test_assert_self_compare():
    x = 7
    assert helper(x) == helper(x)  # assert-self-compare: expected computed by same expression


def test_genuine_assertion():
    # Negative control inside the fixture: a real assertion must NOT be flagged.
    assert helper(2) == 4
