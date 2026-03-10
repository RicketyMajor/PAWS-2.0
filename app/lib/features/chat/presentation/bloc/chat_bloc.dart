// The presentation layer contains the BLoCs (business logic), screens (UI), and widgets.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../data/chat_repository.dart';
import '../../domain/message_model.dart';
import '../../../pets/data/matches_repository.dart';
import '../../../reviews/data/reviews_repository.dart';

// =========================================================================
// Enums
// =========================================================================

/// Represents the status of an asynchronous report operation.
enum ReportStatus { initial, loading, success, failure }

/// Represents the status of an asynchronous review operation.
enum ReviewStatus { initial, loading, success, failure }

// =========================================================================
// Events
// =========================================================================

abstract class ChatEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

/// Dispatched to initialize the chat screen for a specific match.
class InitChat extends ChatEvent {
  final int matchId;
  final String? initialStatus;
  final bool isRescuer;

  InitChat(this.matchId, {this.initialStatus, this.isRescuer = false});
  @override
  List<Object?> get props => [matchId, initialStatus, isRescuer];
}

/// Dispatched when the user sends a message.
class SendMessageEvent extends ChatEvent {
  final String content;
  SendMessageEvent(this.content);
  @override
  List<Object?> get props => [content];
}

/// Dispatched when the user decides to unmatch.
class UnmatchChatEvent extends ChatEvent {}

/// Dispatched when the user reports the other user in the chat.
class ReportUserEvent extends ChatEvent {
  final int reportedId;
  final String category;
  final String description;

  ReportUserEvent({required this.reportedId, required this.category, required this.description});
  @override
  List<Object?> get props => [reportedId, category, description];
}

/// Dispatched when the user submits a review.
class SendReviewEvent extends ChatEvent {
  final double rating;
  final String comment;

  SendReviewEvent({required this.rating, required this.comment});
  @override
  List<Object?> get props => [rating, comment];
}

/// Internal event dispatched when a new message is received from the WebSocket.
class _ReceiveMessageEvent extends ChatEvent {
  final ChatMessage message;
  _ReceiveMessageEvent(this.message);
  @override
  List<Object?> get props => [message];
}

// =========================================================================
// States
// =========================================================================

abstract class ChatState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ChatLoading extends ChatState {}

/// The main state for the chat screen, containing all necessary UI data.
class ChatLoaded extends ChatState {
  final List<ChatMessage> messages;
  final int matchId;
  final int myUserId;
  final bool isLocked;
  final String lockReason;
  final String? error;
  final ReportStatus reportStatus;
  final ReviewStatus reviewStatus;

  ChatLoaded({
    required this.messages,
    required this.matchId,
    required this.myUserId,
    this.isLocked = false,
    this.lockReason = '',
    this.error,
    this.reportStatus = ReportStatus.initial,
    this.reviewStatus = ReviewStatus.initial,
  });

  @override
  List<Object?> get props => [messages, matchId, myUserId, isLocked, lockReason, error, reportStatus, reviewStatus];

  /// Creates a copy of the current state with updated values.
  ChatLoaded copyWith({
    List<ChatMessage>? messages,
    int? matchId,
    int? myUserId,
    bool? isLocked,
    String? lockReason,
    String? error,
    ReportStatus? reportStatus,
    ReviewStatus? reviewStatus,
  }) {
    return ChatLoaded(
      messages: messages ?? this.messages,
      matchId: matchId ?? this.matchId,
      myUserId: myUserId ?? this.myUserId,
      isLocked: isLocked ?? this.isLocked,
      lockReason: lockReason ?? this.lockReason,
      error: error, // Error is nullable, so we don't default it.
      reportStatus: reportStatus ?? this.reportStatus,
      reviewStatus: reviewStatus ?? this.reviewStatus,
    );
  }
}

class ChatError extends ChatState {
  final String message;
  ChatError(this.message);
  @override
  List<Object?> get props => [message];
}


// =========================================================================
// BLoC
// =========================================================================

/// Manages the state and business logic for a single chat screen.
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository chatRepository;
  final MatchesRepository matchesRepository;
  final ReviewsRepository reviewsRepository;
  final _storage = const FlutterSecureStorage();

  StreamSubscription? _messagesSubscription;
  int _currentMatchId = 0;
  int _myUserId = 0;

  ChatBloc({
    required this.chatRepository,
    required this.matchesRepository,
    required this.reviewsRepository,
  }) : super(ChatLoading()) {
    
    on<InitChat>(_onInitChat);
    on<SendMessageEvent>(_onSendMessage);
    on<_ReceiveMessageEvent>(_onReceiveMessage);
    on<UnmatchChatEvent>(_onUnmatch);
    on<ReportUserEvent>(_onReportUser);
    on<SendReviewEvent>(_onSendReview);
  }

  Future<void> _onInitChat(InitChat event, Emitter<ChatState> emit) async {
    emit(ChatLoading());
    _currentMatchId = event.matchId;

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final decodedToken = JwtDecoder.decode(token);
        _myUserId = decodedToken['user_id'] ?? int.parse(decodedToken['sub']);
      }

      final historyJson = await chatRepository.getHistory(_currentMatchId);
      final history = historyJson.map((json) => ChatMessage.fromJson(json, _myUserId)).toList();
      history.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      bool isLocked = false;
      String reason = '';
      if (event.initialStatus != null && event.initialStatus != 'accepted') {
        isLocked = true;
        reason = _getLockReason(event.initialStatus!, event.isRescuer);
      }

      emit(ChatLoaded(messages: history, matchId: _currentMatchId, myUserId: _myUserId, isLocked: isLocked, lockReason: reason));

      // Set up WebSocket listener for new messages.
      await chatRepository.connect();
      _messagesSubscription?.cancel();
      _messagesSubscription = chatRepository.messages.listen((dynamic data) {
        try {
          final decoded = jsonDecode(data);
          if (decoded['type'] == 'new_message' && decoded['payload']['match_id'] == _currentMatchId) {
            add(_ReceiveMessageEvent(ChatMessage.fromJson(decoded['payload'], _myUserId)));
          } else if (decoded['type'] == 'error') {
            print("BACKEND WS ERROR: ${decoded['payload']['message']}");
          }
        } catch (e) {
          print("Error parsing WebSocket message: $e");
        }
      });

    } catch (e) {
      emit(ChatError("Error loading chat: $e"));
    }
  }

  void _onSendMessage(SendMessageEvent event, Emitter<ChatState> emit) {
    final currentState = state;
    if (currentState is ChatLoaded && !currentState.isLocked) {
      chatRepository.sendMessage(_currentMatchId, event.content);
    }
  }

  void _onReceiveMessage(_ReceiveMessageEvent event, Emitter<ChatState> emit) {
    final currentState = state;
    if (currentState is ChatLoaded) {
      emit(currentState.copyWith(messages: [event.message, ...currentState.messages]));
    }
  }

  Future<void> _onUnmatch(UnmatchChatEvent event, Emitter<ChatState> emit) async {
    final currentState = state;
    if (currentState is ChatLoaded) {
      try {
        await matchesRepository.unmatch(_currentMatchId);
        emit(currentState.copyWith(isLocked: true, lockReason: 'You have left this chat.'));
      } catch (e) {
        emit(currentState.copyWith(error: "Could not leave chat: ${e.toString()}"));
      }
    }
  }

  Future<void> _onReportUser(ReportUserEvent event, Emitter<ChatState> emit) async {
    final currentState = state;
    if (currentState is ChatLoaded) {
      emit(currentState.copyWith(reportStatus: ReportStatus.loading));
      try {
        await chatRepository.reportUser(
          reportedId: event.reportedId,
          matchId: _currentMatchId,
          category: event.category,
          description: event.description,
        );
        emit(currentState.copyWith(reportStatus: ReportStatus.success));
      } catch (e) {
        emit(currentState.copyWith(reportStatus: ReportStatus.failure, error: e.toString()));
      }
      // Reset status to allow for future actions.
      emit(currentState.copyWith(reportStatus: ReportStatus.initial, error: null));
    }
  }

  Future<void> _onSendReview(SendReviewEvent event, Emitter<ChatState> emit) async {
    final currentState = state;
    if (currentState is ChatLoaded) {
      emit(currentState.copyWith(reviewStatus: ReviewStatus.loading));
      try {
        await reviewsRepository.createReview(
          matchId: _currentMatchId,
          rating: event.rating,
          comment: event.comment,
        );
        emit(currentState.copyWith(reviewStatus: ReviewStatus.success));
      } catch (e) {
        emit(currentState.copyWith(reviewStatus: ReviewStatus.failure, error: e.toString()));
      }
      // Reset status.
      emit(currentState.copyWith(reviewStatus: ReviewStatus.initial, error: null));
    }
  }

  String _getLockReason(String status, bool isRescuer) {
    switch (status) {
      case 'pet_deleted': return isRescuer ? 'You have removed this pet.' : 'This pet listing has been removed.';
      case 'adopter_left': return 'The adopter has left the chat.';
      case 'rescuer_left': return 'The rescuer has left the chat.';
      case 'peer_left': return 'The other user has left the chat.';
      default: return 'Chat ended.';
    }
  }

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    return super.close();
  }
}
