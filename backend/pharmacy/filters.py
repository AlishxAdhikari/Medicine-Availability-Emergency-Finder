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
    # Combined lookup: pharmacy identity (name/address/district) OR any
    # medicine that pharmacy stocks (name/generic/brand). Without the stock
    # join, searching "Amoxicillin" only returned shops whose *name* contained
    # that word — not shops that actually carry the drug.
    search = django_filters.CharFilter(method='filter_search')

    class Meta:
        model = Pharmacy
        fields = ['district', 'is_24_hour', 'is_verified']

    def filter_search(self, queryset, name, value):
        value = (value or '').strip()
        if not value:
            return queryset
        return queryset.filter(
            Q(name__icontains=value)
            | Q(address__icontains=value)
            | Q(district__icontains=value)
            | Q(stock_entries__medicine__name__icontains=value)
            | Q(stock_entries__medicine__generic_name__icontains=value)
            | Q(stock_entries__medicine__brand__icontains=value)
        ).distinct()
