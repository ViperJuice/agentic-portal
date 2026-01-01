import 'dart:async';
import 'package:dio/dio.dart';
import 'package:eventflux/eventflux.dart';

/// Client for AgentAPI HTTP endpoints
class AgentApiClient {
  final String baseUrl;
  final Dio _dio;

  AgentApiClient({required this.baseUrl}) : _dio = Dio(BaseOptions(baseUrl: baseUrl));

  /// GET /status - Returns agent state (stable or running)
  Future<AgentStatus> getStatus() async {
    final response = await _dio.get('/status');
    return AgentStatus.fromJson(response.data);
  }

  /// GET /messages - Returns conversation history
  Future<List<Message>> getMessages() async {
    final response = await _dio.get('/messages');
    final messages = response.data['messages'] as List;
    return messages.map((m) => Message.fromJson(m)).toList();
  }

  /// POST /message - Send message to agent
  Future<bool> sendMessage(String content, {MessageType type = MessageType.user}) async {
    final response = await _dio.post('/message', data: {
      'content': content,
      'type': type.name,
    });
    return response.data['ok'] == true;
  }

  /// GET /events - Subscribe to SSE stream
  Stream<AgentEvent> subscribeToEvents() {
    final controller = StreamController<AgentEvent>.broadcast();

    EventFlux.instance.connect(
      EventFluxConnectionType.get,
      '$baseUrl/events',
      onSuccessCallback: (response) {
        response.stream?.listen((event) {
          if (event.event == 'message_update') {
            controller.add(MessageUpdateEvent.fromJson(event.data));
          } else if (event.event == 'status_change') {
            controller.add(StatusChangeEvent.fromJson(event.data));
          }
        });
      },
      onError: (error) => controller.addError(error),
      autoReconnect: true,
    );

    return controller.stream;
  }
}

enum MessageType { user, raw }

class AgentStatus {
  final String status; // 'stable' or 'running'
  final String agentType;

  AgentStatus({required this.status, required this.agentType});

  factory AgentStatus.fromJson(Map<String, dynamic> json) => AgentStatus(
    status: json['status'],
    agentType: json['agent_type'],
  );

  bool get isStable => status == 'stable';
  bool get isRunning => status == 'running';
}

class Message {
  final int id;
  final String content;
  final String role; // 'user' or 'agent'
  final DateTime time;

  Message({required this.id, required this.content, required this.role, required this.time});

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'],
    content: json['content'],
    role: json['role'],
    time: DateTime.parse(json['time']),
  );

  bool get isUser => role == 'user';
  bool get isAgent => role == 'agent';
}

abstract class AgentEvent {}

class MessageUpdateEvent extends AgentEvent {
  final int id;
  final String role;
  final String message;
  final DateTime time;

  MessageUpdateEvent({required this.id, required this.role, required this.message, required this.time});

  factory MessageUpdateEvent.fromJson(Map<String, dynamic> json) => MessageUpdateEvent(
    id: json['id'],
    role: json['role'],
    message: json['message'],
    time: DateTime.parse(json['time']),
  );
}

class StatusChangeEvent extends AgentEvent {
  final String status;
  final String agentType;

  StatusChangeEvent({required this.status, required this.agentType});

  factory StatusChangeEvent.fromJson(Map<String, dynamic> json) => StatusChangeEvent(
    status: json['status'],
    agentType: json['agent_type'],
  );
}
