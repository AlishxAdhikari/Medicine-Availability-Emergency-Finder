from django.urls import path
from .views import StockSyncView

urlpatterns = [
    path('stock/sync/', StockSyncView.as_view(), name='stock-sync'),
]