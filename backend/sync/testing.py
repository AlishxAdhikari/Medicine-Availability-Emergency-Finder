"""Helpers for asserting on what sync/signals.py broadcast.

Not a test module itself -- it lives here rather than under tests/ so both
sync/tests/test_signals.py and pharmacy/tests_owner.py can import it without
one app reaching into the other's test package.
"""


def sent_events(mock_async_to_sync, event_type=None):
    """Every (group_name, event) pair the signal pushed, newest last.

    Tests used to assert on `mock.called` alone, which was a fair proxy back
    when a committed transaction produced at most one message. It stopped being
    one once a single commit could produce three -- stock_transaction to the
    owner group, then stock_level and possibly stock_alert to the public one --
    because `called` is then true no matter which of them fired. Every test
    reading it as "the low-stock alert fired" silently started passing for the
    wrong reason. Filter by type and say which message you mean.
    """
    calls = mock_async_to_sync.return_value.call_args_list
    pairs = [(c.args[0], c.args[1]) for c in calls]
    if event_type is None:
        return pairs
    return [(group, event) for group, event in pairs if event['type'] == event_type]


def alert_events(mock_async_to_sync):
    """Just the low-stock warnings."""
    return sent_events(mock_async_to_sync, 'stock_alert')


def level_events(mock_async_to_sync):
    """Just the routine quantity updates every watching client receives."""
    return sent_events(mock_async_to_sync, 'stock_level')
