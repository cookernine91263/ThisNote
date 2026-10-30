import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';

IconData kindIcon(NoteKind kind) => switch (kind) {
      NoteKind.diary => LucideIcons.calendarHeart,
      NoteKind.essay => LucideIcons.feather,
      NoteKind.note => LucideIcons.penLine,
    };

IconData? weatherIcon(String? key) => switch (key) {
      'sunny' => LucideIcons.sun,
      'cloudy' => LucideIcons.cloudSun,
      'overcast' => LucideIcons.cloudy,
      'rain' => LucideIcons.cloudRain,
      'snow' => LucideIcons.cloudSnow,
      'wind' => LucideIcons.wind,
      _ => null,
    };

IconData moodIcon(Mood mood) => switch (mood) {
      Mood.calm => LucideIcons.waves,
      Mood.glad => LucideIcons.sun,
      Mood.full => LucideIcons.sparkles,
      Mood.tired => LucideIcons.moon,
      Mood.low => LucideIcons.cloudRain,
    };
