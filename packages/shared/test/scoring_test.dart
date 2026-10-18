import 'package:beatdrop_shared/beatdrop_shared.dart';
import 'package:test/test.dart';

void main() {
  final drop = songDropTime.inMicroseconds;

  test('offset is relative to song start plus drop time', () {
    expect(
      tapOffsetMicros(tapAt: 1000 + drop - 30000, songStart: 1000),
      -30000,
    );
    expect(
      tapOffsetMicros(tapAt: 1000 + drop + 120000, songStart: 1000),
      120000,
    );
    expect(tapOffsetMicros(tapAt: null, songStart: 1000), isNull);
  });

  test('an early tap beats a closer late one; misses last', () {
    final ranked = rankResults([
      const PlayerResult(id: 'a', name: 'A'),
      const PlayerResult(
        id: 'b',
        name: 'B',
        offset: Duration(milliseconds: -200),
      ),
      const PlayerResult(
        id: 'c',
        name: 'C',
        offset: Duration(milliseconds: 40),
      ),
    ]);
    expect(ranked.map((r) => r.id), ['b', 'c', 'a']);
  });

  test('any late tap ranks below every early one', () {
    PlayerResult r(String id, int ms) => PlayerResult(
      id: id,
      name: id,
      offset: Duration(milliseconds: ms),
    );
    final ranked = rankResults([
      r('late0.1', 100),
      const PlayerResult(id: 'miss', name: 'miss'),
      r('early1', -1000),
      r('late2', 2000),
      r('exact', 0),
      r('early0.3', -300),
    ]);
    expect(ranked.map((r) => r.id), [
      'exact',
      'early0.3',
      'early1',
      'late0.1',
      'late2',
      'miss',
    ]);
  });

  test('results round-trip through JSON', () {
    const r = PlayerResult(
      id: 'x',
      name: 'X',
      offset: Duration(microseconds: -5),
    );
    expect(PlayerResult.fromJson(r.toJson()).offset, r.offset);
    const miss = PlayerResult(id: 'y', name: 'Y');
    expect(PlayerResult.fromJson(miss.toJson()).missed, isTrue);
  });

  test('room codes avoid confusable letters', () {
    for (var i = 0; i < 100; i++) {
      final code = generateRoomCode();
      expect(normalizeRoomCode(code.toLowerCase()), code);
    }
    expect(normalizeRoomCode('ABCDEI'), isNull);
    expect(normalizeRoomCode('ABC'), isNull);
  });
}
