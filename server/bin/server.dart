import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beatdrop_server/room_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';

Future<void> main() async {
  final rooms = RoomServer();

  final ws = webSocketHandler((channel, _) {
    final session = Session((msg) => channel.sink.add(jsonEncode(msg)));
    channel.stream.listen(
      (data) {
        if (data is! String) return;
        try {
          rooms.handle(session, (jsonDecode(data) as Map).cast());
        } on FormatException {
          // Ignore malformed frames.
        } on TypeError {
          // Ignore frames that aren't JSON objects.
        }
      },
      onDone: () => rooms.disconnect(session),
      cancelOnError: true,
    );
  }, pingInterval: const Duration(seconds: 20));

  FutureOr<Response> handler(Request r) => r.url.path == 'ws'
      ? ws(r)
      : Response.ok('beatdrop ok, ${rooms.roomCount} rooms');

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('Listening on ws://${server.address.host}:${server.port}/ws');
}
