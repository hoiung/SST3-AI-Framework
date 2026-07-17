"""Single-quote main-guard entry point (#547 Stage-4 #447 recall gate).

The double-quote main pattern misses `if __name__ == '__main__'` (quote-significant
ast-grep pattern text). This file's ONLY entry point is a single-quote main guard, so
its presence in entry-points output is a direct RED->GREEN lock on the single-quote fix.
The `!=` line below is a negative control: an inverse guard is NOT an entry point.
"""


def run() -> int:
    return 0


if __name__ != '__main__':  # negative control — inverse guard, must NOT be flagged
    pass

if __name__ == '__main__':
    run()
