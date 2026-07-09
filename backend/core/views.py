<<<<<<< HEAD
from django.shortcuts import render

# Create your views here.
=======
from django.contrib.auth import authenticate
from django.contrib.auth import get_user_model
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from .serializers import LoginIdentifierSerializer, RegisterSerializer, UserSerializer

User = get_user_model()


class RegisterView(generics.CreateAPIView):
    """POST /api/v1/auth/register/

    Public endpoint. Login is handled separately by simplejwt's
    TokenObtainPairView (see core/urls.py) — this view only creates the
    account, it does not issue tokens itself, so the client always does an
    explicit login step right after registering.
    """
    permission_classes = [permissions.AllowAny]
    serializer_class = RegisterSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return_data = UserSerializer(user).data
        headers = self.get_success_headers(serializer.data)
        return Response(return_data, status=201, headers=headers)


class LoginIdentifierView(generics.GenericAPIView):
    """POST /api/v1/auth/login-identifier/

    Allows login with either an email or phone number by resolving the user
    first and then issuing JWTs via simplejwt.
    """
    permission_classes = [permissions.AllowAny]
    serializer_class = LoginIdentifierSerializer

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
            # If no user matched by username/email, try to find a user by
            # phone number stored on their MedicalProfile.
            try:
                from .models import MedicalProfile
                profile = MedicalProfile.objects.filter(phone_number__iexact=identifier).first()
                user = profile.user if profile is not None else None
            except Exception:
                user = None
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
>>>>>>> 30db5e0 (athentication as well as pharmacy search is done but biometric login and database required for proper API integration and maps)
