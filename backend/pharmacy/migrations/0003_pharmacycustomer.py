from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('pharmacy', '0002_pharmacyowner'),
    ]

    operations = [
        migrations.CreateModel(
            name='PharmacyCustomer',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=200)),
                ('phone', models.CharField(db_index=True, max_length=20)),
                ('membership', models.CharField(choices=[('NONE', 'None'), ('SILVER', 'Silver'), ('GOLD', 'Gold'), ('PLATINUM', 'Platinum')], default='NONE', max_length=20)),
                ('membership_id', models.CharField(blank=True, max_length=40)),
                ('notes', models.CharField(blank=True, max_length=300)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('pharmacy', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='customers', to='pharmacy.pharmacy')),
            ],
            options={
                'ordering': ['name'],
                'unique_together': {('pharmacy', 'phone')},
            },
        ),
    ]
