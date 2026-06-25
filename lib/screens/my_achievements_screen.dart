import 'package:flutter/material.dart';
import '../services/achievement_service.dart';

class MyAchievementsScreen extends StatefulWidget {
  const MyAchievementsScreen({super.key});
  @override State<MyAchievementsScreen> createState() => _MyAchievementsScreenState();
}

class _MyAchievementsScreenState extends State<MyAchievementsScreen> {
  List<Map<String, String>> _achievements = [];
  bool _loading = true;

  @override void initState() { super.initState(); _loadAchievements(); }

  Future<void> _loadAchievements() async {
    _achievements = await AchievementService.getAll();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的成就')),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
        const Text('已解锁', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ..._achievements.where((a) => a['unlocked'] == 'true').map(_buildCard),
        if (_achievements.any((a) => a['unlocked'] == 'false')) ...[
          const SizedBox(height: 20),
          const Text('未解锁', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._achievements.where((a) => a['unlocked'] == 'false').map(_buildCard),
        ],
      ]),
    );
  }

  Widget _buildCard(Map<String, String> a) {
    final unlocked = a['unlocked'] == 'true';
    return Card(
      color: unlocked ? null : Colors.grey.shade100,
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: unlocked
              ? Image.asset(a['img']!, width: 48, height: 48, fit: BoxFit.cover)
              : Container(width: 48, height: 48, color: Colors.grey.shade300, child: const Icon(Icons.lock, color: Colors.white, size: 24)),
        ),
        title: unlocked
            ? Text(a['title']!, style: const TextStyle(fontWeight: FontWeight.w600))
            : const Text('???', style: TextStyle(color: Colors.grey)),
        subtitle: unlocked
            ? Text(a['tag']!, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
            : const Text('完成相关任务即可解锁', style: TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: unlocked ? const Icon(Icons.emoji_events, color: Color(0xFFF9CA24)) : null,
      ),
    );
  }
}
