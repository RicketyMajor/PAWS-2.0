import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../chat/presentation/screens/chat_screen.dart';
import '../../domain/match_model.dart';
import '../../data/matches_repository.dart';

/// A screen that displays an adopter's matches, separated into
/// "Active Chats" and "Pending Requests" tabs.
class AdopterMatchesScreen extends StatefulWidget {
  /// Callback to update the unread message badge in the parent layout.
  final Function(int)? onBadgeUpdate;

  const AdopterMatchesScreen({super.key, this.onBadgeUpdate});

  @override
  State<AdopterMatchesScreen> createState() => _AdopterMatchesScreenState();
}

class _AdopterMatchesScreenState extends State<AdopterMatchesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Match> _acceptedMatches = [];
  List<Match> _pendingMatches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllData();
  }

  /// Loads both accepted and pending matches from the repository.
  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final matchesRepo = context.read<MatchesRepository>();
      
      // 1. Fetch active chats.
      final matches = await matchesRepo.getAdopterAcceptedMatches();
      if (mounted) {
        setState(() => _acceptedMatches = matches);
        // Calculate and update the unread badge count.
        final totalUnread = matches.fold(0, (sum, m) => sum + m.unreadCount);
        widget.onBadgeUpdate?.call(totalUnread);
      }

      // 2. Fetch pending requests.
      final pending = await matchesRepo.getAdopterPendingMatches();
      if (mounted) setState(() => _pendingMatches = pending);

    } catch (e) {
      print("Error in AdopterMatchesScreen: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Matches"),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFE91E63),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFE91E63),
          tabs: const [Tab(text: "Active Chats"), Tab(text: "Pending")],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildAcceptedList(), _buildPendingList()],
            ),
    );
  }

  /// Builds the list view for accepted matches (active chats).
  Widget _buildAcceptedList() {
    if (_acceptedMatches.isEmpty) {
      return _buildEmptyState("You have no active chats", Icons.chat_bubble_outline);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _acceptedMatches.length,
      itemBuilder: (context, index) {
        final match = _acceptedMatches[index];
        final pet = match.pet;
        final rescuerName = pet?.ownerName ?? 'Rescuer';
        final rescuerPhoto = pet?.ownerPhotoUrl;
        final hasUnread = match.hasUnreadMessages;

        return Card(
          color: hasUnread ? Colors.pink[50] : Colors.white,
          margin: const EdgeInsets.only(bottom: 12),
          elevation: hasUnread ? 4 : 1,
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Stack(children: [
              CircleAvatar(radius: 28, backgroundImage: ImageHelper.getProvider(pet?.imageUrl), backgroundColor: Colors.grey[200]),
              if (hasUnread)
                Positioned(right: 0, top: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
            ]),
            title: Text(
              pet?.name ?? 'Pet',
              style: TextStyle(
                decoration: match.isPetDeleted ? TextDecoration.lineThrough : null,
                color: match.isPetDeleted ? Colors.grey : Colors.black,
                fontWeight: hasUnread ? FontWeight.w900 : FontWeight.bold,
              ),
            ),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                hasUnread ? "${match.unreadCount} new messages" : "Rescuer: $rescuerName",
                style: TextStyle(color: hasUnread ? const Color(0xFFE91E63) : Colors.grey[700], fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal),
              ),
              if (match.isPetDeleted) const Text("⚠️ Listing removed", style: TextStyle(color: Colors.red, fontSize: 12)),
              if (match.isRescuerLeft) const Text("⚠️ Rescuer left the chat", style: TextStyle(color: Colors.orange, fontSize: 12)),
            ]),
            trailing: hasUnread
                ? Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Color(0xFFE91E63), shape: BoxShape.circle), child: Text(match.unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))
                : const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatScreen(
                  matchId: match.id,
                  petId: match.petId,
                  peerName: rescuerName,
                  peerId: pet?.ownerId ?? 0,
                  peerPhotoUrl: rescuerPhoto,
                  isPetDeleted: match.isPetDeleted,
                  isPeerLeft: match.isRescuerLeft,
                )),
              );
              _loadAllData(); // Reload data on return to update read status.
            },
          ),
        );
      },
    );
  }

  /// Builds the list view for pending match requests.
  Widget _buildPendingList() {
    if (_pendingMatches.isEmpty) {
      return _buildEmptyState("You have no pending requests", Icons.access_time);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pendingMatches.length,
      itemBuilder: (context, index) {
        final match = _pendingMatches[index];
        final pet = match.pet;
        return Card(
          color: Colors.grey[50],
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: ClipRRect(borderRadius: BorderRadius.circular(30), child: ImageHelper.getImage(pet?.imageUrl, width: 60, height: 60, fit: BoxFit.cover)),
            title: Text(pet?.name ?? 'No Name', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text("Waiting for response...", style: TextStyle(color: Colors.orange)),
            trailing: const Icon(Icons.hourglass_empty, color: Colors.orange),
          ),
        );
      },
    );
  }

  /// Builds a generic placeholder for when a list is empty.
  Widget _buildEmptyState(String msg, IconData icon) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 60, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(msg, style: TextStyle(color: Colors.grey[600], fontSize: 16)),
      ]),
    );
  }
}
