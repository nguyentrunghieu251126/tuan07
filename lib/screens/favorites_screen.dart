import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/favorite_db.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<FavoriteRoute> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await FavoriteDb.instance.getAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _delete(FavoriteRoute r) async {
    await FavoriteDb.instance.delete(r.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tuyến đường yêu thích')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(child: Text('Chưa có tuyến nào được lưu.'))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = _items[i];
                return ListTile(
                  leading: CircleAvatar(child: Icon(r.mode.icon)),
                  title: Text(r.name),
                  subtitle: Text(
                    '${r.startLabel}\n→ ${r.endLabel}\n'
                    '${formatDistance(r.distanceMeters)} · ${formatDuration(r.durationSeconds)} · ${r.mode.label}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(r),
                  ),
                  onTap: () => Navigator.pop(context, r),
                );
              },
            ),
    );
  }
}
