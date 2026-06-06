from django.contrib.gis.db import models as gis_models
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name='Pharmacy',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=255)),
                ('address', models.CharField(max_length=255)),
                ('phone', models.CharField(blank=True, max_length=32)),
                ('location', gis_models.PointField(blank=True, geography=True, null=True)),
                ('stock_status', models.CharField(choices=[('available', 'Available'), ('low_stock', 'Low Stock'), ('out_of_stock', 'Out of Stock')], default='available', max_length=20)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={
                'ordering': ['name'],
            },
        ),
        migrations.CreateModel(
            name='BloodBank',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=255)),
                ('address', models.CharField(max_length=255)),
                ('phone', models.CharField(blank=True, max_length=32)),
                ('location', gis_models.PointField(blank=True, geography=True, null=True)),
                ('blood_stock_status', models.JSONField(blank=True, default=dict)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={
                'ordering': ['name'],
            },
        ),
        migrations.CreateModel(
            name='EssentialMedicine',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=255)),
                ('generic_name', models.CharField(blank=True, max_length=255)),
                ('availability', models.CharField(choices=[('available', 'Available'), ('low_stock', 'Low Stock'), ('out_of_stock', 'Out of Stock')], default='available', max_length=20)),
                ('manual_notes', models.TextField(blank=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('pharmacy', models.ForeignKey(blank=True, null=True, on_delete=models.CASCADE, related_name='essential_medicines', to='core.pharmacy')),
            ],
            options={
                'ordering': ['name'],
            },
        ),
    ]
