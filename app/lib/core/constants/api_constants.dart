// Package constants contains application-wide constant values.
import 'package:flutter/foundation.dart';

/// Defines the network endpoints and base URLs for the API.
///
/// NOTE: This class appears to conflict with `EnvironmentConfig`. Both define
/// `baseUrl` and `wsUrl`. This version uses `kReleaseMode` to switch between
/// development and production, which might be a more standard Flutter approach.
/// Consider consolidating the logic into a single file.
class ApiConstants {
  // --- Base URLs ---
  // `kReleaseMode` is `true` for production builds (e.g., app bundle, Vercel)
  // and `false` for debug builds (e.g., running in an emulator).
  static const String baseUrl = kReleaseMode
      ? 'https://paws-backend-g9sh.onrender.com/api/v1' // Production URL
      : 'http://10.0.2.2:8080/api/v1';                 // Development URL for Android Emulator

  static const String wsUrl = kReleaseMode
      ? 'wss://paws-backend-g9sh.onrender.com/api/v1' // Production WebSocket URL
      : 'ws://10.0.2.2:8080/api/v1';                  // Development WebSocket URL

  // --- Auth Endpoints ---
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String verifyOtp = '/auth/otp/verify';
  static const String switchRole = '/auth/switch-role';

  // --- Match Endpoints ---
  static const String swipeDeck = '/matches/candidates';
  static const String swipeAction = '/matches/swipe';
  static const String pendingRequests = '/matches/requests';

  // --- User & Social Endpoints ---
  static const String reportUser = '/report';
  static const String reviews = '/reviews';      // POST for creating/updating reviews
  static const String userReviews = '/users';    // GET /users/:id/reviews

  // --- Admin Endpoints ---
  static const String adminReports = '/admin/reports';
  static const String adminResolve = '/admin/reports'; // Used for POST with /:id/resolve
  static const String blacklistSearch = '/blacklist/search';
}
