import 'package:flutter/material.dart';

/// Placeholder for the pharmacy owner's stock editor. Task 9 fills this in;
/// it exists now so the `/owner` route registered in main.dart compiles and
/// role-aware login routing can be exercised end to end.
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
