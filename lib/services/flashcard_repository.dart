import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/flashcard.dart';

const _boxName = 'flashcard_progress';

class FlashcardRepository {
  static final FlashcardRepository _instance = FlashcardRepository._();
  FlashcardRepository._();
  factory FlashcardRepository() => _instance;

  List<Flashcard>? _cards;

  Future<List<Flashcard>> loadAll() async {
    if (_cards != null) return _cards!;
    final raw = await rootBundle.loadString('assets/seeds/flashcards_ny.json');
    final list = jsonDecode(raw) as List<dynamic>;
    _cards = list.map((e) => Flashcard.fromJson(e as Map<String, dynamic>)).toList();
    return _cards!;
  }

  Future<Box<String>> _box() => Hive.openBox<String>(_boxName);

  Future<CardStatus> getStatus(String id) async {
    final box = await _box();
    final raw = box.get(id);
    return switch (raw) {
      'mastered' => CardStatus.mastered,
      'learning' => CardStatus.learning,
      _ => CardStatus.fresh,
    };
  }

  Future<void> setStatus(String id, CardStatus status) async {
    final box = await _box();
    await box.put(id, status.name);
  }

  Future<Map<String, CardStatus>> allStatuses() async {
    final box = await _box();
    final cards = await loadAll();
    return {
      for (final c in cards)
        c.id: switch (box.get(c.id)) {
          'mastered' => CardStatus.mastered,
          'learning' => CardStatus.learning,
          _ => CardStatus.fresh,
        }
    };
  }

  Future<void> resetSection(String section) async {
    final cards = await loadAll();
    final box = await _box();
    for (final c in cards.where((c) => c.section == section)) {
      await box.delete(c.id);
    }
  }
}
