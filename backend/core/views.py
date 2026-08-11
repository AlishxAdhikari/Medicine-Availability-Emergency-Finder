from django.contrib.auth import authenticate, get_user_model
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView

from .models import MedicalProfile
from .serializers import (
    LoginIdentifierSerializer,
    MedicalProfileSerializer,
    RegisterSerializer,
    SharedProfileSerializer,
    UserSerializer,
)

User = get_user_model()


class ThrottledLoginView(TokenObtainPairView):
    """simplejwt's login view, rate-limited.

    Subclassed purely to attach a throttle scope: the endpoint is
    unauthenticated and password-checking, so without one it will answer
    guesses as fast as they arrive. Rate lives in settings.py under
    DEFAULT_THROTTLE_RATES['login'].
    """
    throttle_scope = 'login'


class RegisterView(generics.CreateAPIView):
    """POST /api/v1/auth/register/"""
    permission_classes = [permissions.AllowAny]
    serializer_class = RegisterSerializer
    throttle_scope = 'register'

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return_data = UserSerializer(user).data
        headers = self.get_success_headers(serializer.data)
        return Response(return_data, status=201, headers=headers)


class LoginIdentifierView(generics.GenericAPIView):
    """POST /api/v1/auth/login-identifier/"""
    permission_classes = [permissions.AllowAny]
    serializer_class = LoginIdentifierSerializer
    throttle_scope = 'login'

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        identifier = serializer.validated_data['identifier'].strip()
        password = serializer.validated_data['password']

        user = None
        if '@' in identifier:
            user = User.objects.filter(email__iexact=identifier).first()
        else:
            user = User.objects.filter(username__iexact=identifier).first()

        if user is None:
            # Neither an email nor a username matched, so treat the identifier
            # as a phone number. .filter().first() already returns None when
            # there is no match -- this used to sit inside a bare
            # `except Exception: user = None`, which caught nothing this lookup
            # actually raises and instead turned genuine database errors into
            # "no active account found", hiding real outages behind what looks
            # like a wrong password.
            profile = MedicalProfile.objects.filter(phone_number__iexact=identifier).first()
            user = profile.user if profile is not None else None
            if user is None:
                return Response({'detail': 'No active account found with the given credentials'}, status=status.HTTP_401_UNAUTHORIZED)

        authenticated_user = authenticate(request=request, username=user.username, password=password)
        if authenticated_user is None:
            return Response({'detail': 'No active account found with the given credentials'}, status=status.HTTP_401_UNAUTHORIZED)

        refresh = RefreshToken.for_user(authenticated_user)
        return Response({
            'refresh': str(refresh),
            'access': str(refresh.access_token),
            'user': UserSerializer(authenticated_user).data,
        }, status=status.HTTP_200_OK)


class CurrentUserView(generics.RetrieveAPIView):
    """GET /api/v1/auth/me/ — the signed-in user, same shape as the `user` key
    on the login response.

    Exists because `role` is derived from the PharmacyOwner link (see
    UserSerializer) and can therefore change between logins: staff link or
    unlink a pharmacy in admin whenever they like. Any client that resumes a
    session without going through login-identifier -- the biometric path in
    login_screen.dart -- would otherwise be routing off whatever role was true
    the last time a password was typed. Losing ownership self-corrects (the
    owner API 403s), but GAINING it does not: nothing would ever tell the app.

    Like MedicalProfileView there is no id in the URL; it always resolves to
    whoever's token this is.
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user


class MedicalProfileView(generics.RetrieveUpdateAPIView):
    """GET/PUT /api/v1/auth/medical-id/ — the logged-in user's own profile.

    Only usable by a signed-in user (permission_classes below). There is no
    <id> in the URL on purpose: get_object() always resolves to "whoever's
    JWT this is", so there's no way to request someone else's profile by
    guessing a different id/pk in the URL.
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = MedicalProfileSerializer

    def get_object(self):
        # get_or_create so a brand-new user who has never filled in their
        # medical info yet still gets a 200 with mostly-blank fields,
        # instead of a confusing 404 on their very first visit to this screen.
        profile, _ = MedicalProfile.objects.get_or_create(user=self.request.user)
        return profile


class SharedProfileView(generics.RetrieveAPIView):
    """GET /api/v1/auth/medical-id/share/<uuid:share_token>/ — public,
    no login required. This is what a first-responder's phone hits after
    scanning the user's QR code, so permission_classes is deliberately
    AllowAny. The narrower SharedProfileSerializer (no name/email/phone)
    is what keeps this safe to expose without auth.
    """
    permission_classes = [permissions.AllowAny]
    serializer_class = SharedProfileSerializer
    throttle_scope = 'shared_profile'
    queryset = MedicalProfile.objects.all()
    lookup_field = 'share_token'