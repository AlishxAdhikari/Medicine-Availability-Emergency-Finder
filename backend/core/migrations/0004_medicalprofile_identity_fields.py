from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0003_phone_number_unique'),
    ]

    operations = [
        migrations.AddField(
            model_name='medicalprofile',
            name='full_name',
            field=models.CharField(blank=True, max_length=200),
        ),
        migrations.AddField(
            model_name='medicalprofile',
            name='date_of_birth',
            field=models.CharField(blank=True, max_length=32),
        ),
        migrations.AddField(
            model_name='medicalprofile',
            name='gender',
            field=models.CharField(blank=True, max_length=32),
        ),
        migrations.AddField(
            model_name='medicalprofile',
            name='address',
            field=models.CharField(blank=True, max_length=300),
        ),
    ]
