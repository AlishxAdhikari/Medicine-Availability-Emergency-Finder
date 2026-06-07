import django_filters
from django.db.models import Q
from .models import Pharmacy, Medicine, BloodBank, AmbulanceProvider

class PharmacyFilter(django_filters.FilterSet):
    search = django_filters.CharFilter(method='filter_search')
    name = django_filters.CharFilter(lookup_expr='icontains')
    district = django_filters.CharFilter(lookup_expr='iexact')
    is_24h = django_filters.BooleanFilter()
    verification_status = django_filters.CharFilter(lookup_expr='iexact')
    is_active = django_filters.BooleanFilter()

    class Meta:
        model = Pharmacy
        fields = ['search', 'name', 'district', 'is_24h', 'verification_status', 'is_active']

    def filter_search(self, queryset, name, value):
        return queryset.filter(
            Q(name__icontains=value) |
            Q(address__icontains=value) |
            Q(district__icontains=value)
        )


class MedicineFilter(django_filters.FilterSet):
    search = django_filters.CharFilter(method='filter_search')
    name = django_filters.CharFilter(lookup_expr='icontains')
    generic_name = django_filters.CharFilter(lookup_expr='icontains')
    brand_name = django_filters.CharFilter(lookup_expr='icontains')
    category = django_filters.NumberFilter()
    is_essential = django_filters.BooleanFilter()
    requires_prescription = django_filters.BooleanFilter()
    dosage_form = django_filters.CharFilter(lookup_expr='icontains')

    class Meta:
        model = Medicine
        fields = ['search', 'name', 'generic_name', 'brand_name', 'category', 'is_essential', 'requires_prescription', 'dosage_form']

    def filter_search(self, queryset, name, value):
        return queryset.filter(
            Q(name__icontains=value) |
            Q(generic_name__icontains=value) |
            Q(brand_name__icontains=value)
        )


class BloodBankFilter(django_filters.FilterSet):
    search = django_filters.CharFilter(method='filter_search')
    blood_group = django_filters.CharFilter(method='filter_blood_group')
    name = django_filters.CharFilter(lookup_expr='icontains')
    district = django_filters.CharFilter(lookup_expr='iexact')
    is_24h = django_filters.BooleanFilter()
    is_active = django_filters.BooleanFilter()

    class Meta:
        model = BloodBank
        fields = ['search', 'blood_group', 'name', 'district', 'is_24h', 'is_active']

    def filter_search(self, queryset, name, value):
        return queryset.filter(
            Q(name__icontains=value) |
            Q(address__icontains=value) |
            Q(district__icontains=value)
        )

    def filter_blood_group(self, queryset, name, value):
        return queryset.filter(
            blood_stocks__blood_group__iexact=value
        ).exclude(
            blood_stocks__stock_level='unavailable'
        ).distinct()


class AmbulanceProviderFilter(django_filters.FilterSet):
    search = django_filters.CharFilter(method='filter_search')
    hospital_name = django_filters.CharFilter(lookup_expr='icontains')
    service_type = django_filters.CharFilter(lookup_expr='iexact')
    district = django_filters.CharFilter(lookup_expr='iexact')
    is_24h = django_filters.BooleanFilter()
    has_icu = django_filters.BooleanFilter()
    has_oxygen = django_filters.BooleanFilter()
    is_active = django_filters.BooleanFilter()

    class Meta:
        model = AmbulanceProvider
        fields = ['search', 'hospital_name', 'service_type', 'district', 'is_24h', 'has_icu', 'has_oxygen', 'is_active']

    def filter_search(self, queryset, name, value):
        return queryset.filter(
            Q(hospital_name__icontains=value) |
            Q(address__icontains=value) |
            Q(district__icontains=value)
        )
