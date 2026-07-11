<<<<<<< HEAD
from django.db import models

# Create your models here.
=======
import uuid

from django.conf import settings
from django.db import models


class MedicalProfile(models.Model):
    """One-to-one medical record for a registered user.

    Created lazily on first access (see core.views.MedicalProfileView) rather
    than via a post-save signal on User, so registration itself stays fast
    and free of side effects.
    """
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='medical_profile',
    )
    blood_group = models.CharField(max_length=5, blank=True)
    height_cm = models.FloatField(null=True, blank=True)
    weight_kg = models.FloatField(null=True, blank=True)
    allergies = models.TextField(blank=True)
    chronic_conditions = models.TextField(blank=True)
    current_medications = models.TextField(blank=True)
    emergency_contact_name = models.CharField(max_length=100, blank=True)
    emergency_contact_phone = models.CharField(max_length=20, blank=True)
    # User's primary phone number (optional). Stored here to support
    # login-by-phone without extending the User model.
    phone_number = models.CharField(max_length=20, blank=True)

    # Randomly generated, exposed in the QR code instead of the user's own
    # identity — anyone who has the token can read the profile (that's the
    # point, for first responders), but it doesn't leak who the user is.
    share_token = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Medical profile for {self.user.username}"
>>>>>>> 30db5e0 (athentication as well as pharmacy search is done but biometric login and database required for proper API integration and maps)
