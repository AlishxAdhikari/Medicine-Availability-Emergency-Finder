from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.db import transaction
from rest_framework import serializers

from .models import MedicalProfile


class LoginIdentifierSerializer(serializers.Serializer):
    identifier = serializers.CharField(required=True)
    password = serializers.CharField(required=True)

User = get_user_model()


class RegisterSerializer(serializers.ModelSerializer):
    """Handles new-user signup.

    password is write_only so it never round-trips in a response, and is
    run through Django's own validators (length, common-password checks,
    etc.) via validate_password rather than a hand-rolled regex.

    full_name is separate from username on purpose: Django's username field
    only allows letters/digits/@/./+/-/_ (no spaces), so a person's actual
    name -- which usually has spaces -- can never safely BE the username.
    The client is expected to generate a valid username (e.g. from the
    email) and send the real name here instead, so it can be persisted and
    shown back to the user on any device, not just kept in local storage.
    """
    password = serializers.CharField(write_only=True, validators=[validate_password])

    phone = serializers.CharField(write_only=True, required=False)
    full_name = serializers.CharField(write_only=True, required=False, allow_blank=True)

    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'password', 'phone', 'full_name')
        extra_kwargs = {
            'email': {'required': True},
        }

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError('A user with this email already exists.')
        return value

    def validate_phone(self, value):
        """MedicalProfile.phone_number has no DB-level unique constraint, and
        LoginIdentifierView resolves a phone-based login with .first() on a
        match -- so without this check, two accounts could silently share a
        phone number, and whichever registered second would be permanently
        unable to log in via phone (the lookup always resolves to the first
        match, so the second account's own correct password would just
        appear to fail). Blocking the duplicate here, at registration, is
        what prevents that ambiguity from being created in the first place.
        """
        value = value.strip()
        if value and MedicalProfile.objects.filter(phone_number__iexact=value).exists():
            raise serializers.ValidationError('A user with this phone number already exists.')
        return value

    @transaction.atomic
    def create(self, validated_data):
        """Creates the user and their MedicalProfile as one unit.

        The whole method is atomic because the phone number lives on the
        profile, not the user. Previously the profile write was wrapped in a
        bare `except Exception: pass`, so a failure there left a user who had
        registered with a phone number but had none stored -- and login by
        phone would then fail forever, with no error at signup to explain it
        and nothing in the logs. Registration failing loudly is far better
        than an account that is quietly half-created: the user can simply try
        again, whereas the broken account needs manual repair.
        """
        phone = validated_data.pop('phone', '').strip()
        full_name = validated_data.pop('full_name', '').strip()

        # create_user (not create) is what actually hashes the password via
        # PBKDF2 instead of storing it in plain text.
        user = User.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            password=validated_data['password'],
        )

        if full_name:
            first_name, _, last_name = full_name.partition(' ')
            user.first_name = first_name
            user.last_name = last_name
            user.save(update_fields=['first_name', 'last_name'])

        # Always create the profile, so /medical-id/ has a row to read and
        # login-by-phone can resolve the user.
        profile, _ = MedicalProfile.objects.get_or_create(user=user)
        if phone:
            profile.phone_number = phone
            profile.save(update_fields=['phone_number'])
        return user


class UserSerializer(serializers.ModelSerializer):
    """Read-only representation of the logged-in user, returned alongside
    the register/login response so the client doesn't need a second round
    trip. Includes first_name/last_name so the app can show the person's
    real name on any device, not just the one they registered on.

    role and pharmacy are derived from the PharmacyOwner link rather than
    stored, so they can never disagree with it. The client routes on role
    straight out of the login response -- see login_screen.dart.
    """
    role = serializers.SerializerMethodField()
    pharmacy = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'first_name', 'last_name', 'role', 'pharmacy')

    def get_role(self, obj):
        return 'pharmacy_owner' if hasattr(obj, 'pharmacy_owner') else 'user'

    def get_pharmacy(self, obj):
        owner_link = getattr(obj, 'pharmacy_owner', None)
        if owner_link is None:
            return None
        return {'id': owner_link.pharmacy_id, 'name': owner_link.pharmacy.name}


class MedicalProfileSerializer(serializers.ModelSerializer):
    """Full profile, for the logged-in owner only (GET/PUT /medical-id/).

    share_token is read_only: it's generated automatically when the
    MedicalProfile row is created (see models.py), the user never sets it
    themselves, but the app still needs to read it so it can build the
    QR-code / share link.
    """

    class Meta:
        model = MedicalProfile
        fields = (
            'id', 'blood_group', 'height_cm', 'weight_kg', 'allergies',
            'chronic_conditions', 'current_medications',
            'emergency_contact_name', 'emergency_contact_phone',
            'phone_number', 'share_token', 'updated_at',
        )
        read_only_fields = ('id', 'share_token', 'updated_at')


class SharedProfileSerializer(serializers.ModelSerializer):
    """Public, read-only view of a profile for the /medical-id/share/<token>/
    endpoint — what a first responder sees when they scan a QR code.

    Deliberately excludes anything that identifies the person: no user,
    username, email, or phone_number. Only medically-relevant fields.
    """

    class Meta:
        model = MedicalProfile
        fields = (
            'blood_group', 'height_cm', 'weight_kg', 'allergies',
            'chronic_conditions', 'current_medications',
            'emergency_contact_name', 'emergency_contact_phone',
        )