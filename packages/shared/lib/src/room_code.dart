import 'dart:math';

/// Letters that can't be mistaken for each other or for digits (no I, L, O).
const roomCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ';
const roomCodeLength = 6;

String generateRoomCode([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < roomCodeLength; i++)
      roomCodeAlphabet.codeUnitAt(r.nextInt(roomCodeAlphabet.length)),
  ]);
}

/// Upper-cases [input] and strips spaces; returns null unless it's a valid code.
String? normalizeRoomCode(String input) {
  final code = input.replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (code.length != roomCodeLength) return null;
  for (final c in code.split('')) {
    if (!roomCodeAlphabet.contains(c)) return null;
  }
  return code;
}
