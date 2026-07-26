from django.apps import AppConfig


class SyncConfig(AppConfig):
    name = 'sync'
    def ready(self):
        # Importing here (not at module top) registers the @receiver in
        # signals.py with Django's signal dispatcher. If this import is
        # skipped or placed elsewhere, the signal silently never fires --
        # no error, alerts just never get sent. This is the #1 gotcha with
        # Django signals.
        import sync.signals  # noqa: F401