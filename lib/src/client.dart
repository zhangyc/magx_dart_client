import 'package:chopper/chopper.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'api_client.dart';
import 'connection/connection.dart';
import 'connection/ws_connection.dart';
import 'room/room.dart';
import 'room/room_data.dart';
import 'service.dart';
import 'token_storage.dart';

class Authentication {
  final String id;
  final String token;
  final dynamic data;

  Authentication({
    this.id,
    this.token,
    this.data,
  });

  factory Authentication.fromJson(Map<String, dynamic> json) => Authentication(
        id: json['id'],
        token: json['token'],
        data: json['data'],
      );
}

class CTParams {
  final String url;
  final List<String> protocols;

  CTParams(this.url, {this.protocols});
}

typedef ConnectionBuilder = Connection Function(CTParams params);

class MagxClientParams {
  final num port;
  final String address;
  final bool secure;
  final String id;
  final String token;
  final dynamic data;
  final ConnectionBuilder transport;

  MagxClientParams({
    @required this.address,
    this.secure = false,
    this.port,
    this.id,
    this.token,
    this.data,
    this.transport,
  });
}

class MagxClient {
  final TokenStorage tokenStorage;
  @visibleForTesting
  MagxApiClient api;

  String address;
  bool secure;
  num port;
  final ConnectionBuilder transport;

  String get uri => '${secure ? "https" : "http"}://$address${port != null ? ":$port" : ""}/magx';

  MagxClient(
    MagxClientParams params, {
    this.tokenStorage,
    http.Client client,
    Iterable interceptors = const [],
  }) : transport = params.transport ?? ((p) => WSConnection(p)) {
    address = params.address ?? 'localhost';
    port = params.port;
    secure = params.secure;

    api = MagxApiClient.create(
      baseUrl: uri,
      tokenStorage: tokenStorage,
      client: client,
      interceptors: interceptors,
    );
  }

  Future<Response<Authentication>> authenticateGuest({@required String deviceId, String fmsToken}) => api.service
      .authenticateGuest(
        deviceId: deviceId,
        fmsToken: fmsToken,
      )
      .then(
        (value) => value.copyWith(body: value.body != null ? Authentication.fromJson(value.body) : null),
      );

  Future<Response<Authentication>> authenticateGoogle({@required String accessToken, String fmsToken}) {
    return api.service
        .authenticateGoogle(
          accessToken: accessToken,
          fmsToken: fmsToken,
        )
        .then(
          (value) => value.copyWith(body: value.body != null ? Authentication.fromJson(value.body) : null),
        );
  }

  Future<Response<Authentication>> authenticateApple({@required String accessToken, String fmsToken}) => api.service
      .authenticateApple(
        accessToken: accessToken,
        fmsToken: fmsToken,
      )
      .then(
        (value) => value.copyWith(body: value.body != null ? Authentication.fromJson(value.body) : null),
      );

  Future<Response<Authentication>> verify({String token}) {
    return api.service
        .verify(
          token: token ?? tokenStorage.token,
        )
        .then(
          (value) => value.copyWith(body: value.body != null ? Authentication.fromJson(value.body) : null),
        );
  }

  Future<Response<String>> getRoom(String id) => api.service.getRoom(id).then(
        (value) => value.copyWith(body: value.body as String),
      );

  Future<Response<Iterable<dynamic>>> getRooms(List<String> names) => api.service.getRooms(names).then(
        (value) => value.copyWith(
          body: value.body != null ? value.body as Iterable<dynamic> : null,
        ),
      );

  Future<Response<Room>> joinRoom(RoomData description) => api.service.joinRoom(description.id).then(
        (value) async {
          if (value.isSuccessful) {
            final description = RoomData.fromJson(value.body);
            return value.copyWith(body: await connectRoom(description));
          }
          return value.copyWith(body: null);
        },
      );

  Future leaveRoom(String id) => api.service.leaveRoom(id);

  Future<Response<Room>> createRoom(String name, {Map<String, dynamic> options}) => api.service
          .createRoom(
        CreateRoomPayload(name, options),
      )
          .then((value) async {
        if (value.isSuccessful) {
          return value.copyWith(body: await connectRoom(RoomData.fromJson(value.body)));
        } else {
          return value.copyWith(body: null);
        }
      });

  Future<Room> connectRoom(RoomData roomData, {bool reconnect}) async => Room(this, roomData).ready.then(
        (value) => value..send(reconnect == true ? Message.reconnected() : Message.joined()),
      );
}
