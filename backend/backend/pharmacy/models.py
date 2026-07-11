from django.db import models


class Pharmacy(models.Model):
    name = models.CharField(max_length=200)
    address = models.CharField(max_length=300)
    district = models.CharField(max_length=100, db_index=True)
    latitude = models.FloatField()
    longitude = models.FloatField()
    is_24_hour = models.BooleanField(default=False)
    is_verified = models.BooleanField(default=False)
    phone = models.CharField(max_length=20, blank=True)

    class Meta:
        verbose_name_plural = 'Pharmacies'

    def __str__(self):
        return self.name


class Medicine(models.Model):
    name = models.CharField(max_length=200, db_index=True)
    generic_name = models.CharField(max_length=200, blank=True, db_index=True)
    brand = models.CharField(max_length=200, blank=True)
    category = models.CharField(max_length=100)
    dosage_form = models.CharField(max_length=50)
    strength = models.CharField(max_length=50)
    is_essential = models.BooleanField(default=False)
    requires_prescription = models.BooleanField(default=False)

    def __str__(self):
        return self.name


class PharmacyMedicineStock(models.Model):
    pharmacy = models.ForeignKey(Pharmacy, on_delete=models.CASCADE, related_name='stock_entries')
    medicine = models.ForeignKey(Medicine, on_delete=models.CASCADE)
    quantity = models.PositiveIntegerField(default=0)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    low_threshold = models.PositiveIntegerField(default=10)

    class Meta:
        unique_together = ('pharmacy', 'medicine')

    def __str__(self):
        return f"{self.medicine.name} @ {self.pharmacy.name} ({self.quantity})"