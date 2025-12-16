// lib/pages/music_selection_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

class MusicSelectionPage extends StatefulWidget {
  const MusicSelectionPage({super.key});

  @override
  State<MusicSelectionPage> createState() => _MusicSelectionPageState();
}

class _MusicSelectionPageState extends State<MusicSelectionPage> {
  final _searchController = TextEditingController();
  final _player = AudioPlayer();

  final String _jamendoKey = 'edb5792f';
  final String _jamendoUrl = 'https://api.jamendo.com/v3.0/tracks';

  List<Map<String, dynamic>> _tracks = [];
  bool _loading = true;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _loadMusic();
  }

  @override
  void dispose() {
    _player.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /* ---------------- MUSIC LOADER ---------------- */
  Future<void> _loadMusic([String query = 'travel']) async {
    setState(() => _loading = true);

    try {
      final uri = Uri.parse(
        '$_jamendoUrl'
        '?client_id=$_jamendoKey'
        '&format=json'
        '&limit=20'
        '&search=$query'
        '&order=popularity_total',
      );

      final res = await http.get(uri);
      if (res.statusCode != 200) throw Exception('API failed');

      final List results = jsonDecode(res.body)['results'];

      _tracks = results
          .where((e) => e['audio'] != null)
          .map((e) => {
                'id': e['id'].toString(),
                'title': e['name'],
                'artist': e['artist_name'],
                'url': e['audio'],
                'duration': e['duration'],
                'album_image': e['album_image'],
                'genre': e['musicinfo']?['genre'] ?? '',
              })
          .toList();
    } catch (_) {
      _tracks = [];
    }

    setState(() => _loading = false);
  }

  /* ---------------- PLAY / PAUSE ---------------- */
  Future<void> _togglePlay(Map<String, dynamic> track) async {
    final url = track['url'];

    if (_currentUrl == url) {
      // Same track - toggle play/pause
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }

    // New track - stop current and play new
    _currentUrl = url;
    setState(() {}); // Update UI immediately

    await _player.stop();
    await _player.setUrl(url);
    await _player.play();
  }

  /* ---------------- SEEK BAR ---------------- */
  Widget _buildSeekBar() {
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;

        return StreamBuilder<Duration?>(
          stream: _player.durationStream,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds.toDouble();
            final currentMs = position.inMilliseconds.toDouble();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Slider(
                    min: 0,
                    max: maxMs > 0 ? maxMs : 1,
                    value: currentMs.clamp(0, maxMs),
                    onChanged: (value) {
                      _player.seek(Duration(milliseconds: value.toInt()));
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /* ---------------- DURATION FORMATTER ---------------- */
  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  /* ---------------- TRACK DURATION FORMATTER ---------------- */
  String _formatTrackDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /* ---------------- BUILD TRACK TILE ---------------- */
  Widget _buildTrackTile(Map<String, dynamic> track, PlayerState playerState) {
    final url = track['url'];
    final isCurrent = _currentUrl == url;
    final playing = playerState.playing;
    final processingState = playerState.processingState;

    // Determine icon based on state
    IconData icon;
    Color iconColor;

    if (isCurrent) {
      if (processingState == ProcessingState.loading ||
          processingState == ProcessingState.buffering) {
        icon = Icons.hourglass_top;
        iconColor = Colors.orange;
      } else if (playing) {
        icon = Icons.pause_circle_filled;
        iconColor = Colors.purple;
      } else {
        icon = Icons.play_circle_filled;
        iconColor = Colors.grey;
      }
    } else {
      icon = Icons.play_circle_filled;
      iconColor = Colors.grey;
    }

    // Get album image if available
    final albumImage = track['album_image'];

    return Column(
      children: [
        ListTile(
          leading: albumImage != null && albumImage.isNotEmpty
              ? CircleAvatar(
                  backgroundImage: NetworkImage(albumImage),
                  radius: 24,
                )
              : CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey[200],
                  child: Icon(
                    Icons.music_note,
                    color: Colors.grey[600],
                  ),
                ),
          title: Text(
            track['title'],
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isCurrent ? Colors.purple : Colors.black,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track['artist'],
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    Icons.timer,
                    size: 10,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatTrackDuration(track['duration']),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (track['genre'] != null && track['genre'].isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          track['genre'],
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent ? Colors.purple.withOpacity(0.1) : Colors.transparent,
                ),
                child: IconButton(
                  icon: Icon(
                    icon,
                    color: iconColor,
                    size: 30,
                  ),
                  onPressed: () => _togglePlay(track),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 30,
                ),
                onPressed: () {
                  Navigator.pop(context, {
                    'musicUrl': track['url'],
                    'musicTitle': track['title'],
                    'musicArtist': track['artist'],
                    'musicDuration': track['duration'],
                  });
                },
              ),
            ],
          ),
          onTap: () => _togglePlay(track),
        ),
        
        // Show seek bar only for currently playing track
        if (isCurrent && _player.duration != null) _buildSeekBar(),
        
        const Divider(height: 1, thickness: 0.5),
      ],
    );
  }

  /* ---------------- UI ---------------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Select Music',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadMusic(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search music...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.purple, width: 2),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadMusic();
                        },
                      )
                    : null,
              ),
              onSubmitted: _loadMusic,
            ),
          ),

          // Now Playing Indicator (if any track is playing)
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final playerState = snapshot.data;
              final playing = playerState?.playing ?? false;
              final currentTrack = _tracks.firstWhere(
                (track) => track['url'] == _currentUrl,
                orElse: () => {},
              );

              if (currentTrack.isEmpty || !playing) {
                return const SizedBox.shrink();
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.05),
                  border: const Border(
                    top: BorderSide(color: Colors.purple, width: 0.5),
                    bottom: BorderSide(color: Colors.purple, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.music_note, color: Colors.purple, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Now Playing: ${currentTrack['title']}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.purple,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            currentTrack['artist'],
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.purple,
                      size: 20,
                    ),
                  ],
                ),
              );
            },
          ),

          // Tracks List
          Expanded(
            child: StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snapshot) {
                final playerState = snapshot.data ?? PlayerState(false, ProcessingState.idle);

                if (_loading) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading music from Jamendo...'),
                      ],
                    ),
                  );
                }

                if (_tracks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.music_off,
                          size: 60,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No music found',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => _loadMusic(),
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) {
                    return _buildTrackTile(_tracks[index], playerState);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}