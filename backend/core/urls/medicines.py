from django.urls import path, include
from rest_framework.routers import DefaultRouter
from core.views import MedicineViewSet, MedicineCategoryViewSet

router = DefaultRouter()
router.register(r'categories', MedicineCategoryViewSet, basename='category')
router.register(r'', MedicineViewSet, basename='medicine')

urlpatterns = [
    path('', include(router.urls)),
]
