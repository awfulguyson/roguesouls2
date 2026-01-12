import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/app_config.dart';

class GameService {
  IO.Socket? socket;
  Function(Map<String, dynamic>)? onPlayerJoined;
  Function(Map<String, dynamic>)? onPlayerMoved;
  Function(Map<String, dynamic>)? onPlayerLeft;
  Function(Map<String, dynamic>)? onChatMessage;
  Function(List<dynamic>)? onPlayersList;

  void connect() {
    socket = IO.io(AppConfig.websocketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket!.connect();

    socket!.on('connect', (_) {
      print('Connected to game server');
    });

    socket!.on('game:players', (data) {
      if (onPlayersList != null) {
        onPlayersList!(data as List<dynamic>);
      }
    });

    socket!.on('player:joined', (data) {
      if (onPlayerJoined != null) {
        onPlayerJoined!(data as Map<String, dynamic>);
      }
    });

    socket!.on('player:moved', (data) {
      if (onPlayerMoved != null) {
        onPlayerMoved!(data as Map<String, dynamic>);
      }
    });

    socket!.on('player:left', (data) {
      if (onPlayerLeft != null) {
        onPlayerLeft!(data as Map<String, dynamic>);
      }
    });

    socket!.on('chat:broadcast', (data) {
      if (onChatMessage != null) {
        onChatMessage!(data as Map<String, dynamic>);
      }
    });
  }

  void joinGame(String characterId, String name) {
    socket?.emit('player:join', {'characterId': characterId, 'name': name});
  }

  void movePlayer(double x, double y) {
    socket?.emit('player:move', {'x': x, 'y': y});
  }

  void sendChatMessage(String message) {
    socket?.emit('chat:message', {'message': message});
  }

  void disconnect() {
    socket?.disconnect();
    socket = null;
  }
}

