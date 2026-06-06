from django.contrib.gis.db import models


class Pharmacy(models.Model):
    class StockStatus(models.TextChoices):
        AVAILABLE = 'available', 'Available'
        LOW_STOCK = 'low_stock', 'Low Stock'
        OUT_OF_STOCK = 'out_of_stock', 'Out of Stock'

    name = models.CharField(max_length=255)
    address = models.CharField(max_length=255)
    phone = models.CharField(max_length=32, blank=True)
    location = models.PointField(geography=True, null=True, blank=True)
    stock_status = models.CharField(max_length=20, choices=StockStatus.choices, default=StockStatus.AVAILABLE)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name']

    def __str__(self) -> str:
        return self.name


class BloodBank(models.Model):
    name = models.CharField(max_length=255)
    address = models.CharField(max_length=255)
    phone = models.CharField(max_length=32, blank=True)
    location = models.PointField(geography=True, null=True, blank=True)
    blood_stock_status = models.JSONField(default=dict, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name']

    def __str__(self) -> str:
        return self.name


class EssentialMedicine(models.Model):
    class Availability(models.TextChoices):
        AVAILABLE = 'available', 'Available'
        LOW_STOCK = 'low_stock', 'Low Stock'
        OUT_OF_STOCK = 'out_of_stock', 'Out of Stock'

    name = models.CharField(max_length=255)
    generic_name = models.CharField(max_length=255, blank=True)
    pharmacy = models.ForeignKey(Pharmacy, related_name='essential_medicines', on_delete=models.CASCADE, null=True, blank=True)
    availability = models.CharField(max_length=20, choices=Availability.choices, default=Availability.AVAILABLE)
    manual_notes = models.TextField(blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name']

    def __str__(self) -> str:
        return self.name
