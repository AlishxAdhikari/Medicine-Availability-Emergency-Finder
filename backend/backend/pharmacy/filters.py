import django_filters
from django.db.models import Q

from .models import Medicine, Pharmacy


class MedicineFilter(django_filters.FilterSet):
    # One `search` param instead of separate name/generic_name/brand params
    # — matches the report's spec: "searchable by name, generic name, or
    # brand" as a single combined lookup.
    search = django_filters.CharFilter(method='filter_search')

    class Meta:
        model = Medicine
        fields = ['category', 'dosage_form', 'is_essential', 'requires_prescription']

    def filter_search(self, queryset, name, value):
        return queryset.filter(
            Q(name__icontains=value)
            | Q(generic_name__icontains=value)
            | Q(brand__icontains=value)
        )


class PharmacyFilter(django_filters.FilterSet):
    # Mirrors MedicineFilter's pattern: "searchable by name, address, or
    # district" from the report, combined into one param.
    search = django_filters.CharFilter(method='filter_search')

    class Meta:
        model = Pharmacy
        fields = ['district', 'is_24_hour', 'is_verified']

    def filter_search(self, queryset, name, value):
        return queryset.filter(
            Q(name__icontains=value)
            | Q(address__icontains=value)
            | Q(district__icontains=value)
        )
