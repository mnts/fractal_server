import 'package:fractal_server/fractal_server.dart';

void main(List<String> args) {
  FServer(
    port: args.length > 1 ? int.parse(args[1]) : 8800,
  );
}
