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


class EmergencyContact(models.Model):
    """One person to text when the SOS "Alert my contacts" button is used.

    A separate table rather than more columns on MedicalProfile: the Flutter
    editor has always allowed any number of these, and the SMS composer
    addresses all of them at once, so the single
    emergency_contact_name/_phone pair silently discarded everyone after the
    first. MedicalProfile keeps that pair as a mirror of `position=0` -- the
    responder share view and any older build still read it.

    `position` rather than relying on insertion order: the app sends the whole
    list on every save and the first entry is the one that gets mirrored into
    the legacy fields, so "which is primary" has to survive a round trip
    intact.
    """
    profile = models.ForeignKey(
        MedicalProfile,
        on_delete=models.CASCADE,
        related_name='emergency_contacts',
    )
    name = models.CharField(max_length=100)
    relationship = models.CharField(max_length=50, blank=True)
    # Not unique and not validated beyond length: these are typed by a person
    # under stress, and a contact saved without a usable number is better than
    # a save that fails. The client filters unreachable ones out of the SMS
    # (see contactsWithNumbers in emergency_call.dart).
    phone_number = models.CharField(max_length=20, blank=True)
    position = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ['position', 'id']

    def __str__(self):
        return f"{self.name} ({self.phone_number})"
