import django_filters

from .models import AmbulanceProvider, BloodBank


class BloodBankFilter(django_filters.FilterSet):
    # blood_group doesn't live on BloodBank itself -- it lives on the
    # related BloodStock rows -- so this filters "through" the relation
    # rather than filtering a field on BloodBank directly.
    blood_group = django_filters.CharFilter(
        field_name='stock__blood_group', lookup_expr='iexact'
    )

    class Meta:
        model = BloodBank
        fields = ['district', 'blood_group']


class AmbulanceFilter(django_filters.FilterSet):
    class Meta:
        model = AmbulanceProvider
        fields = ['district', 'has_icu', 'has_oxygen', 'is_24_hour', 'service_type']