"""Blindness assertion for sst3-test-vacuity.sh (#567 Ralph Tier-2 break-one-claim).

Every form below is vacuous — it cannot fail — yet sits OUTSIDE the scanner's
AST model (it walks ast.Assert nodes only). The paired expected.json pins
exit 0 / 0 findings: the gate's blindness to these classes is DISCLOSED in the
script header, and this fixture asserts the disclosure stays true
(mutation-verification.md sweep gates 2 + 5). If a future widening makes the
scanner sensitive to any of them, this fixture drifts and forces the header's
not-enumerated list to be updated in the same change.
"""

import unittest

import pytest


class TestUnittestCallForms(unittest.TestCase):
    def test_call_assertions_are_not_ast_assert(self):
        self.assertTrue(True)
        self.assertEqual(1, 1)


def test_pytest_raises_noop():
    with pytest.raises(Exception):
        pass


def test_constant_foldable_not_ast_identical():
    assert len([]) == 0
