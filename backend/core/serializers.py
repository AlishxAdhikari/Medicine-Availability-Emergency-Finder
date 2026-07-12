from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
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
    """
    password = serializers.CharField(write_only=True, validators=[validate_password])

    phone = serializers.CharField(write_only=True, required=False)

    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'password', 'phone')
        extra_kwargs = {
            'email': {'required': True},
        }

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError('A user with this email already exists.')
        return value

    def create(self, validated_data):
        phone = validated_data.pop('phone', '').strip()
        # create_user (not create) is what actually hashes the password via
        # PBKDF2 instead of storing it in plain text.
        user = User.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            password=validated_data['password'],
        )
        # If a phone number was provided, create or update the user's
        # MedicalProfile to store it so login-by-phone can resolve the user.
        try:
            from .models import MedicalProfile
            profile, _ = MedicalProfile.objects.get_or_create(user=user)
            if phone:
                profile.phone_number = phone
                profile.save()
        except Exception:
            # If medical profile isn't available for some reason, don't
            # fail user creation; profile will be created lazily elsewhere.
            pass
        return user


class UserSerializer(serializers.ModelSerializer):
    """Read-only representation of the logged-in user, returned alongside
    the register response so the client doesn't need a second round trip."""

    class Meta:
        model = User
        fields = ('id', 'username', 'email')


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