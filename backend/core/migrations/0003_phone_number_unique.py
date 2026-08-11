from django.db import migrations, models


def blank_phone_numbers_to_null(apps, schema_editor):
    """Rewrites '' to NULL before the unique constraint is applied.

    phone_number was previously `blank=True` with no null, so every profile
    without a phone stores the empty string. Those are all equal to each
    other, so adding UNIQUE while they exist fails immediately on any
    database with more than one phone-less profile. NULLs, by contrast, are
    all distinct for uniqueness purposes, which is exactly the semantics
    "this user has no phone number" needs.
    """
    MedicalProfile = apps.get_model('core', 'MedicalProfile')
    MedicalProfile.objects.filter(phone_number='').update(phone_number=None)


def reject_duplicate_phone_numbers(apps, schema_editor):
    """Fails loudly if real duplicates exist, rather than destroying data.

    Nothing enforced uniqueness before this migration, so two accounts may
    genuinely share a number. We could pick a winner automatically, but that
    silently discards a real phone number and locks the loser out of
    login-by-phone with no trace of why. Stopping with the offending numbers
    named is recoverable; guessing is not.
    """
    MedicalProfile = apps.get_model('core', 'MedicalProfile')
    from django.db.models import Count

    duplicates = (
        MedicalProfile.objects.exclude(phone_number=None)
        .values('phone_number')
        .annotate(n=Count('id'))
        .filter(n__gt=1)
    )
    offenders = [row['phone_number'] for row in duplicates]
    if offenders:
        raise RuntimeError(
            'Cannot add a unique constraint to MedicalProfile.phone_number: '
            'these numbers are used by more than one profile: '
            f'{", ".join(offenders)}. Decide which account keeps each number '
            'and clear it from the others (Django admin, or the shell), then '
            're-run migrate.'
        )


def noop(apps, schema_editor):
    """Reversing needs no data change: '' and NULL both satisfy the old
    nullable-with-no-unique column."""


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0002_medicalprofile_phone_number'),
    ]

    # Order matters. The column has to accept NULL before the data step can
    # write any, and the data has to be clean before UNIQUE is applied --
    # doing it in one AlterField fails on every non-empty database.
    operations = [
        migrations.AlterField(
            model_name='medicalprofile',
            name='phone_number',
            field=models.CharField(blank=True, max_length=20, null=True),
        ),
        migrations.RunPython(blank_phone_numbers_to_null, noop),
        migrations.RunPython(reject_duplicate_phone_numbers, noop),
        migrations.AlterField(
            model_name='medicalprofile',
            name='phone_number',
            field=models.CharField(blank=True, max_length=20, null=True, unique=True),
        ),
    ]
