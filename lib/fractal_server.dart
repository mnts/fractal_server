import 'dart:convert';
import 'dart:io';
import 'package:fractal_base/fractals/device.dart';
import 'package:fractal_socket/index.dart';
import 'package:fractal_utils/random.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:signed_fractal/signed_fractal.dart';

class FServer {
  static final uploadDir = join(FileF.path, 'uploads');
  static const local = '127.0.0.1';
  static const lPort = 8800;

  var host = local;
  var port = lPort;

  FServer({
    this.host = local,
    this.port = lPort,
    required this.buildSocket,
  }) {
    listen();
  }

  ClientFractal Function(DeviceFractal) buildSocket;

  listen() async {
    var server = await HttpServer.bind(
      host,
      port,
    );

    print('Listening on ${server.address.host}:${server.port}');

    server.listen((HttpRequest q) async {
      final ip =
          q.connectionInfo?.remoteAddress ?? q.headers['X-Forwarded-For'];
      print("Request ${q.uri.path} by $ip");

      const headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': '*',
      };

      for (final h in headers.entries) {
        q.response.headers.set(
          h.key,
          h.value,
          preserveHeaderCase: true,
        );
      }

      if (q.uri.path.startsWith('/uploads/')) {
        final hash = basename(q.uri.path);

        final f = File('$uploadDir/$hash');

        if (f.existsSync()) {
          final bytes = f.readAsBytesSync();
          final mimeType = 'application/octet-stream';
          //lookupMimeType(hash);
          q.response
            ..headers.contentType = ContentType.parse(mimeType)
            ..add(bytes)
            ..close();
        } else {
          q.response
            ..statusCode = HttpStatus.notFound
            ..write('File not found')
            ..close();
        }
        return;
      }

      if (q.uri.path.startsWith('/upload')) {
        try {
          upload(q);
        } catch (e) {
          print(e);
          q.response
            ..statusCode = HttpStatus.internalServerError
            ..write('Error')
            ..close();
        }
        return;
      }

      if (q.uri.path.startsWith('/socket')) {
        socket(q);
        //socket.ready(this);
        // distribute messages to the sockets
        //Communication.catalog.doListen(distributor);
      }
    }, onError: (e) {
      print('Error: $e');
    }, cancelOnError: false);
  }

  upload(HttpRequest req) async {
    List<int> dataBytes = [];

    await for (var data in req) {
      dataBytes.addAll(data);
    }

    final boundary = req.headers.contentType!.parameters['boundary'];
    final transformer = MimeMultipartTransformer(boundary!);

    final bodyStream = Stream.fromIterable([dataBytes]);
    final parts = await transformer.bind(bodyStream).toList();
    dataBytes.clear();

    if (!Directory(uploadDir).existsSync()) {
      await Directory(uploadDir).create();
    }
    final bytes = <int>[];
    for (var part in parts) {
      final content = await part.toList();
      bytes.addAll(content[0]);
    }
    parts.clear();

    final hash = FileF.hash(bytes).toString();
    final fw = File('$uploadDir/$hash');
    fw.writeAsBytes(bytes);

    // Send a response to the client
    req.response
      ..statusCode = HttpStatus.ok
      ..write('File uploaded successfully')
      ..close();
  }

  Map<DeviceFractal, ClientFractal> get sockets => ClientFractal.sockets;

  Future<void> socket(HttpRequest req) async {
    final seg = req.uri.path.split('/');
    if (seg.length < 3) {
      req.response
        ..statusCode = HttpStatus.ok
        ..write('Wrong path')
        ..close();
      return;
    }

    final name = seg.length > 2 ? seg[2] : getRandomString(5);
    final device = DeviceFractal.map[name] ??
        DeviceFractal(
          name: name,
        );

    final connection = await WebSocketTransformer.upgrade(req);
    final socket = sockets[device] ??= buildSocket.call(device);

    // send messages to the client
    socket.elements.stream.listen((d) {
      if (connection.readyState == WebSocket.open) {
        if (d is Map<String, dynamic> || d is List) {
          final json = jsonEncode(d);
          print('send to ${socket.from.name} >> $json');
          try {
            connection.add(json);
          } catch (e) {
            print('error $e');
          }
        }
      } else {
        //Remove socket if the connection is already closed
        //sockets.remove(socket.name);
      }
    }, onError: (e) {
      print('socket error: $e');
      //sockets.remove(socket.name);
    }, cancelOnError: false);

    // receive messages from the client
    connection.listen((d) async {
      print('received: $d');
      try {
        final fractal = socket.receive(d);

        /*
        if (fractal is FractalSessionAbs && socket.session != null) {
          print('session');
          fractal.handle(socket.session!);
        }
        */
      } catch (e) {
        print('ws error: $e');
      }
    }, onDone: () {
      connection.close();
      print(
        'Disconnected ${connection.closeCode}#${connection.closeReason}',
      );
      socket.disconnected();
      socket.unSubscribeAll();
    }, onError: (e) {
      print('ws error: $e');
    });
    socket.connected();
  }

  notFound(HttpRequest req) {
    req.response
      ..statusCode = HttpStatus.notFound
      ..write('File not found')
      ..close();
  }

  //final Map<String, FSocket> sockets = {};
}
