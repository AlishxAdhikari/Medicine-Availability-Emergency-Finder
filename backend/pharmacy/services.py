from math import asin, cos, radians, sin, sqrt


def haversine_km(lat1, lon1, lat2, lon2):
    """Great-circle distance between two lat/lng points, in kilometres.

    Plain-Python implementation because the current DB is SQLite (no
    PostGIS). This gets called per-row after the queryset is fetched, which
    is fine at the pharmacy counts in this project (report's 10,000-record
    NFR target) but would want to move to a PostGIS ST_Distance query if the
    dataset grew much larger — see report section 2.5.
    """
    r_km = 6371
    phi1, phi2 = radians(lat1), radians(lat2)
    d_phi = radians(lat2 - lat1)
    d_lambda = radians(lon2 - lon1)
    a = sin(d_phi / 2) ** 2 + cos(phi1) * cos(phi2) * sin(d_lambda / 2) ** 2
    return 2 * r_km * asin(sqrt(a))


def sort_by_proximity(queryset, lat, lng, radius_km=None):
    """Attaches a `.distance_km` attribute to each object and returns a
    list sorted nearest-first. Returns a plain list, not a queryset, since
    the distance can't be computed in SQL without PostGIS.

    If radius_km is given, results further than that are dropped entirely.
    """
    results = []
    for obj in queryset:
        distance = haversine_km(lat, lng, obj.latitude, obj.longitude)
        if radius_km is not None and distance > radius_km:
            continue
        obj.distance_km = round(distance, 2)
        results.append(obj)
    results.sort(key=lambda o: o.distance_km)
    return results
