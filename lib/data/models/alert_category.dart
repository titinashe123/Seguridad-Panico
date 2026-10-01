import 'package:flutter/material.dart';

class AlertCategory {
  final String id;
  final String name;
  final IconData icon;
  final Color iconColor;

  const AlertCategory({
    required this.id,
    required this.name,
    required this.icon,
    this.iconColor = const Color(0xFFFF5252),
  });

  static List<AlertCategory> get defaultCategories => const [
        AlertCategory(
          id: 'robo',
          name: 'ROBO',
          icon: Icons.masks_outlined,
          iconColor: Color(0xFFFF6D00),
        ),
        AlertCategory(
          id: 'accidente',
          name: 'ACCIDENTE',
          icon: Icons.directions_car_filled_outlined,
          iconColor: Color(0xFFFF8A65),
        ),
        AlertCategory(
          id: 'secuestro',
          name: 'SECUESTRO',
          icon: Icons.person_off_rounded,
          iconColor: Color(0xFFFF1744),
        ),
        AlertCategory(
          id: 'incendio',
          name: 'INCENDIO',
          icon: Icons.local_fire_department_outlined,
          iconColor: Color(0xFFFF3B30),
        ),
        AlertCategory(
          id: 'gresca',
          name: 'GRESCA',
          icon: Icons.sports_kabaddi_rounded,
          iconColor: Color(0xFFFF7043),
        ),
        AlertCategory(
          id: 'asesinato',
          name: 'ASESINATO',
          icon: Icons.dangerous_outlined,
          iconColor: Color(0xFFFF3B30),
        ),
      ];

  static AlertCategory get customCategory => const AlertCategory(
        id: 'personalizado',
        name: 'PERSONALIZADO',
        icon: Icons.edit_note_rounded,
        iconColor: Color(0xFFFF9100),
      );
}
