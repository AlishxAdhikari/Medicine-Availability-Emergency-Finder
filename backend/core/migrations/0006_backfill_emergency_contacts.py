"""Moves each profile's single saved contact into the new contact table.

Without this, everyone who had already filled in their Medical ID would open
the app after the upgrade to an empty contact list -- the data is still in
emergency_contact_name/_phone, but nothing reads those into the list any more.
"""

from django.db import migrations


def forwards(apps, schema_editor):
    MedicalProfile = apps.get_model('core', 'MedicalProfile')
    EmergencyContact = apps.get_model('core', 'EmergencyContact')

    profiles = MedicalProfile.objects.exclude(emergency_contact_name='')
    EmergencyContact.objects.bulk_create([
        EmergencyContact(
            profile=profile,
            name=profile.emergency_contact_name,
            relationship='Contact',
            phone_number=profile.emergency_contact_phone or '',
            position=0,
        )
        for profile in profiles
        if not EmergencyContact.objects.filter(profile=profile).exists()
    ])


def backwards(apps, schema_editor):
    """The legacy columns are still maintained as a mirror of position 0, so
    dropping the rows loses only the second and later contacts -- which is
    exactly what the old schema could hold."""
    EmergencyContact = apps.get_model('core', 'EmergencyContact')
    EmergencyContact.objects.all().delete()


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0005_emergencycontact'),
    ]

    operations = [
        migrations.RunPython(forwards, backwards),
    ]
