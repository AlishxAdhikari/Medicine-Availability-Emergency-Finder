from django.db import models


class BloodBank(models.Model):
    name = models.CharField(max_length=200)
    district = models.CharField(max_length=100, db_index=True)
    latitude = models.FloatField()
    longitude = models.FloatField()
    operating_hours = models.CharField(max_length=100)
    phone = models.CharField(max_length=20, blank=True)

    class Meta:
        verbose_name_plural = 'Blood banks'

    def __str__(self):
        return self.name


class BloodStock(models.Model):
    LEVEL_CHOICES = [
        ('adequate', 'Adequate'),
        ('low', 'Low'),
        ('critical', 'Critical'),
        ('unavailable', 'Unavailable'),
    ]
    bank = models.ForeignKey(BloodBank, on_delete=models.CASCADE, related_name='stock')
    blood_group = models.CharField(max_length=5)
    level = models.CharField(max_length=20, choices=LEVEL_CHOICES)

    class Meta:
        # One row per (bank, blood_group) pair -- prevents accidentally
        # creating two "O+" rows for the same bank with conflicting levels.
        unique_together = ('bank', 'blood_group')
        verbose_name_plural = 'Blood stock'

    def __str__(self):
        return f"{self.blood_group} @ {self.bank.name} ({self.level})"


class AmbulanceProvider(models.Model):
    SERVICE_TYPES = [
        ('government', 'Government'),
        ('private', 'Private'),
        ('ngo', 'NGO'),
    ]
    name = models.CharField(max_length=200)
    service_type = models.CharField(max_length=20, choices=SERVICE_TYPES)
    district = models.CharField(max_length=100, db_index=True)
    is_24_hour = models.BooleanField(default=False)
    has_icu = models.BooleanField(default=False)
    has_oxygen = models.BooleanField(default=False)
    phone = models.CharField(max_length=20)

    def __str__(self):
        return self.name