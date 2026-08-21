import uuid

from django.conf import settings
from django.db import models


class MedicalProfile(models.Model):
    """One-to-one medical record for a registered user."""
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='medical_profile',
    )
    # Identity fields the app edits on the Medical ID screen. These used to
    # live only in Flutter memory (and were wiped on every cold start / fetch).
    full_name = models.CharField(max_length=200, blank=True)
    date_of_birth = models.CharField(max_length=32, blank=True)
    gender = models.CharField(max_length=32, blank=True)
    address = models.CharField(max_length=300, blank=True)

    blood_group = models.CharField(max_length=5, blank=True)
    height_cm = models.FloatField(null=True, blank=True)
    weight_kg = models.FloatField(null=True, blank=True)
    allergies = models.TextField(blank=True)
    chronic_conditions = models.TextField(blank=True)
    current_medications = models.TextField(blank=True)
    emergency_contact_name = models.CharField(max_length=100, blank=True)
    emergency_contact_phone = models.CharField(max_length=20, blank=True)
    # unique because LoginIdentifierView resolves a phone-based login with
    # .first() on this column: two profiles sharing a number would make the
    # second account permanently unable to log in by phone, since the lookup
    # always returns the first match and that account's own correct password
    # would simply appear wrong. RegisterSerializer.validate_phone checks this
    # too, but a serializer check alone loses the race between two concurrent
    # signups and does not apply to the admin or a shell session.
    #
    # null (not '') for "no phone": in SQL, NULLs are all distinct for
    # uniqueness purposes, whereas every phone-less profile storing the same
    # empty string would collide with every other one. save() normalises the
    # empty string to None so no caller has to remember this.
    phone_number = models.CharField(max_length=20, blank=True, null=True, unique=True)
    share_token = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def save(self, *args, **kwargs):
        # Blank input arrives as '' from forms, DRF and the admin alike; see
        # the phone_number comment above for why that must not reach the DB.
        if not self.phone_number:
            self.phone_number = None
        super().save(*args, **kwargs)

    def __str__(self):
        return f"Medical profile for {self.user.username}"
