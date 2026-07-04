import 'package:flutter/material.dart';
import '../widgets/dashboard_section.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة الأداء')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(12),
        child: DashboardSection(),
      ),
    );
  }
}
