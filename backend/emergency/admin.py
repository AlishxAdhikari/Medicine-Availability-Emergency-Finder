from django.contrib import admin

from .models import AmbulanceProvider, BloodBank, BloodStock

admin.site.register(BloodBank)
admin.site.register(BloodStock)
admin.site.register(AmbulanceProvider)