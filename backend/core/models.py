from django.contrib.auth.models import User
from django.db import models
from django.core.validators import RegexValidator, MinValueValidator, MaxValueValidator


# ── Shared helpers ─────────────────────────────────────────────────────────────

phone_validator = RegexValidator(
    regex=r'^\+?9779\d{8}$|^\+?977-?\d{7,10}$|^\d{7,15}$',
    message='Enter a valid phone number (Nepal format preferred).'
)


class TimestampMixin(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


# ── Pharmacy ──────────────────────────────────────────────────────────────────

class Pharmacy(TimestampMixin):
    class VerificationStatus(models.TextChoices):
        PENDING = 'pending', 'Pending Verification'
        VERIFIED = 'verified', 'Verified'
        SUSPENDED = 'suspended', 'Suspended'

    name = models.CharField(max_length=255, db_index=True)
    slug = models.SlugField(max_length=300, unique=True, blank=True)
    address = models.CharField(max_length=500)
    district = models.CharField(max_length=100, blank=True, db_index=True)
    phone = models.CharField(max_length=32, blank=True, validators=[phone_validator])
    phone_alt = models.CharField(max_length=32, blank=True, validators=[phone_validator])
    email = models.EmailField(blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    is_24h = models.BooleanField(default=False)
    opens_at = models.TimeField(null=True, blank=True)
    closes_at = models.TimeField(null=True, blank=True)
    is_active = models.BooleanField(default=True, db_index=True)
    verification_status = models.CharField(
        max_length=20,
        choices=VerificationStatus.choices,
        default=VerificationStatus.PENDING,
        db_index=True,
    )
    # The pharmacist/owner who manages this record via the app
    managed_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='managed_pharmacies',
    )

    class Meta:
        ordering = ['name']
        verbose_name_plural = 'pharmacies'
        indexes = [
            models.Index(fields=['district', 'is_active']),
        ]

    def __str__(self) -> str:
        return self.name


# ── Medicine ───────────────────────────────────────────────────────────────────

class MedicineCategory(models.Model):
    name = models.CharField(max_length=100, unique=True)
    icon = models.CharField(max_length=50, blank=True, help_text='Material icon name')

    class Meta:
        ordering = ['name']
        verbose_name_plural = 'medicine categories'

    def __str__(self) -> str:
        return self.name


class Medicine(TimestampMixin):
    """
    Master catalogue entry — not tied to any pharmacy.
    PharmacyMedicineStock links medicines to pharmacies with availability.
    """
    name = models.CharField(max_length=255, db_index=True)
    generic_name = models.CharField(max_length=255, blank=True, db_index=True)
    brand_name = models.CharField(max_length=255, blank=True)
    category = models.ForeignKey(
        MedicineCategory,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='medicines',
    )
    dosage_form = models.CharField(
        max_length=50,
        blank=True,
        help_text='e.g. tablet, syrup, injection, inhaler',
    )
    strength = models.CharField(max_length=50, blank=True, help_text='e.g. 500mg, 5mg/ml')
    description = models.TextField(blank=True)
    is_essential = models.BooleanField(default=False, db_index=True)
    requires_prescription = models.BooleanField(default=False)

    class Meta:
        ordering = ['name']
        unique_together = [['generic_name', 'strength', 'dosage_form']]

    def __str__(self) -> str:
        parts = [self.name]
        if self.strength:
            parts.append(self.strength)
        return ' '.join(parts)


class PharmacyMedicineStock(TimestampMixin):
    """
    Junction: which medicines a pharmacy stocks, and at what availability.
    """
    class Availability(models.TextChoices):
        AVAILABLE = 'available', 'Available'
        LOW_STOCK = 'low_stock', 'Low Stock'
        OUT_OF_STOCK = 'out_of_stock', 'Out of Stock'

    pharmacy = models.ForeignKey(Pharmacy, on_delete=models.CASCADE, related_name='stock')
    medicine = models.ForeignKey(Medicine, on_delete=models.CASCADE, related_name='stock')
    availability = models.CharField(
        max_length=20,
        choices=Availability.choices,
        default=Availability.AVAILABLE,
        db_index=True,
    )
    price_npr = models.DecimalField(
        max_digits=8, decimal_places=2,
        null=True, blank=True,
        validators=[MinValueValidator(0)],
    )
    quantity_on_hand = models.PositiveIntegerField(null=True, blank=True)
    notes = models.TextField(blank=True)
    last_verified_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True
    )

    class Meta:
        unique_together = [['pharmacy', 'medicine']]
        ordering = ['medicine__name']
        indexes = [
            models.Index(fields=['availability', 'pharmacy']),
        ]

    def __str__(self) -> str:
        return f'{self.pharmacy.name} — {self.medicine.name} ({self.availability})'


# ── Blood Bank ────────────────────────────────────────────────────────────────

BLOOD_GROUPS = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']


class BloodBank(TimestampMixin):
    name = models.CharField(max_length=255, db_index=True)
    address = models.CharField(max_length=500)
    district = models.CharField(max_length=100, blank=True, db_index=True)
    phone = models.CharField(max_length=32, blank=True, validators=[phone_validator])
    phone_alt = models.CharField(max_length=32, blank=True, validators=[phone_validator])
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    is_active = models.BooleanField(default=True, db_index=True)
    is_24h = models.BooleanField(default=False)

    class Meta:
        ordering = ['name']

    def __str__(self) -> str:
        return self.name


class BloodStock(TimestampMixin):
    class StockLevel(models.TextChoices):
        ADEQUATE = 'adequate', 'Adequate'
        LOW = 'low', 'Low'
        CRITICAL = 'critical', 'Critical'
        UNAVAILABLE = 'unavailable', 'Unavailable'

    blood_bank = models.ForeignKey(BloodBank, on_delete=models.CASCADE, related_name='blood_stocks')
    blood_group = models.CharField(
        max_length=3,
        choices=[(bg, bg) for bg in BLOOD_GROUPS],
        db_index=True,
    )
    stock_level = models.CharField(
        max_length=15,
        choices=StockLevel.choices,
        default=StockLevel.ADEQUATE,
        db_index=True,
    )
    units_available = models.PositiveIntegerField(null=True, blank=True)
    notes = models.TextField(blank=True)

    class Meta:
        unique_together = [['blood_bank', 'blood_group']]
        ordering = ['blood_group']

    def __str__(self) -> str:
        return f'{self.blood_bank.name} — {self.blood_group} ({self.stock_level})'


# ── Ambulance ─────────────────────────────────────────────────────────────────

class AmbulanceProvider(TimestampMixin):
    class ServiceType(models.TextChoices):
        GOVERNMENT = 'government', 'Government'
        PRIVATE = 'private', 'Private'
        NGO = 'ngo', 'NGO/Charitable'

    hospital_name = models.CharField(max_length=255, db_index=True)
    service_type = models.CharField(
        max_length=15,
        choices=ServiceType.choices,
        default=ServiceType.GOVERNMENT,
        db_index=True,
    )
    contact_number = models.CharField(max_length=32, validators=[phone_validator])
    contact_alt = models.CharField(max_length=32, blank=True, validators=[phone_validator])
    address = models.CharField(max_length=500)
    district = models.CharField(max_length=100, blank=True, db_index=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    is_active = models.BooleanField(default=True, db_index=True)
    is_24h = models.BooleanField(default=True)
    has_icu = models.BooleanField(default=False)
    has_oxygen = models.BooleanField(default=False)
    notes = models.TextField(blank=True)

    class Meta:
        ordering = ['hospital_name']

    def __str__(self) -> str:
        return f'{self.hospital_name} Ambulance'


# ── User Medical ID ───────────────────────────────────────────────────────────

class MedicalProfile(TimestampMixin):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='medical_profile')
    blood_group = models.CharField(
        max_length=3,
        choices=[(bg, bg) for bg in BLOOD_GROUPS],
        blank=True,
    )
    height_cm = models.PositiveSmallIntegerField(
        null=True, blank=True,
        validators=[MinValueValidator(50), MaxValueValidator(250)],
    )
    weight_kg = models.DecimalField(
        max_digits=5, decimal_places=1,
        null=True, blank=True,
        validators=[MinValueValidator(1), MaxValueValidator(500)],
    )
    allergies = models.TextField(blank=True)
    chronic_conditions = models.TextField(blank=True)
    current_medications = models.TextField(blank=True)
    emergency_contact_name = models.CharField(max_length=100, blank=True)
    emergency_contact_phone = models.CharField(
        max_length=32, blank=True, validators=[phone_validator]
    )
    emergency_contact_relation = models.CharField(max_length=50, blank=True)
    # Optional QR-shareable token (read-only for first responders)
    share_token = models.CharField(max_length=64, unique=True, null=True, blank=True)

    class Meta:
        verbose_name = 'Medical Profile'

    def __str__(self) -> str:
        return f'Medical Profile — {self.user.get_full_name() or self.user.username}'