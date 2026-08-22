"""Valid, genuinely-asserting target file: the usage error must come from the
malformed --threshold argument, never from this file's content."""


def test_real():
    value = 2 + 2
    assert value == 4
