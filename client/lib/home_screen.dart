import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_components/livekit_components.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _storeKeyUri = 'uri';
  static const _storeKeyToken = 'token';

  // Local server configuration
  static const String _localServerUrl = 'http://localhost:8000';
  // Hardcoded LiveKit Cloud URL
  static const String _livekitUrl = 'wss://leet-coach-i7fq4obj.livekit.cloud';

  String _url = '';
  String _token = '';
  bool _autoConnecting = false;

  // Fetch token from local server
  Future<String?> _fetchTokenFromServer() async {
    try {
      if (kDebugMode) {
        print('Fetching token from: $_localServerUrl/getToken');
      }

      final response = await http.get(
        Uri.parse('$_localServerUrl/getToken'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token'] as String?;
        if (kDebugMode) {
          print('Successfully fetched token');
        }
        return token;
      } else {
        if (kDebugMode) {
          print('Failed to fetch token: ${response.statusCode} - ${response.body}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching token: $e');
      }
      return null;
    }
  }

  void _readPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _url =
        const bool.hasEnvironment('URL')
            ? const String.fromEnvironment('URL')
            : prefs.getString(_storeKeyUri) ?? _livekitUrl;
    _token =
        const bool.hasEnvironment('TOKEN')
            ? const String.fromEnvironment('TOKEN')
            : prefs.getString(_storeKeyToken) ?? '';
  }

  // Save URL and Token
  Future<void> _writePrefs(String url, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeKeyUri, url);
    await prefs.setString(_storeKeyToken, token);
  }

  // Auto-connect to my-room
  Future<void> _autoConnectToRoom(RoomContext roomCtx) async {
    if (_autoConnecting) return;

    setState(() {
      _autoConnecting = true;
    });

    try {
      // Fetch token from local server
      final token = await _fetchTokenFromServer();

      if (token != null) {
        // Use fetched token and connect
        await _writePrefs(_livekitUrl, token);

        if (kDebugMode) {
          print('Auto-connecting to room: url=$_livekitUrl, token=$token');
        }

        await roomCtx.connect(url: _livekitUrl, token: token);
      } else {
        if (kDebugMode) {
          print('Failed to fetch token, cannot auto-connect');
        }
        // Show error to user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to fetch token from server. Make sure your local server is running.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Auto-connect failed: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to connect: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() {
          _autoConnecting = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _readPrefs();
  }

  /// handle join button pressed, fetch connection details and connect to room.
  // ignore: unused_element
  void _onJoinPressed(RoomContext roomCtx, String url, String token) async {
    if (kDebugMode) {
      print('Joining room: url=$url, token=$token');
    }
    await _writePrefs(url, token);
    try {
      await roomCtx.connect(url: url, token: token);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to join room: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LivekitRoom(
      roomContext: RoomContext(
        enableAudioVisulizer: true,
        onConnected: () {
          if (kDebugMode) {
            print('Connected to my-room');
          }
        },
        onDisconnected: () {
          if (kDebugMode) {
            print('Disconnected from room');
          }
        },
        onError: (error) {
          if (kDebugMode) {
            print('Error: $error');
          }
        },
      ),
      builder: (context, roomCtx) {
        var deviceScreenType = getDeviceType(MediaQuery.of(context).size);

        // Auto-connect when not connected and not already connecting
        if (!roomCtx.connected && !roomCtx.connecting && !_autoConnecting) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _autoConnectToRoom(roomCtx);
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('LiveKit Components - my-room', style: TextStyle(color: Colors.white)),
            actions: [
              /// show clear pin button
              if (roomCtx.connected) const ClearPinButton(),

              /// show connection status
              if (_autoConnecting)
                const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: Stack(
            children: [
              !roomCtx.connected && !roomCtx.connecting && !_autoConnecting
                  /// show prejoin screen if not connected and not auto-connecting
                  ? Prejoin(token: _token, url: _url, onJoinPressed: _onJoinPressed)
                  : _autoConnecting
                  /// show loading screen while auto-connecting
                  ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Connecting to my-room...'),
                        SizedBox(height: 8),
                        Text('Make sure your local server is running on port 8000'),
                      ],
                    ),
                  )
                  : _buildVideoFeedLayout(context, roomCtx, deviceScreenType),

              /// show toast widget
              const Positioned(top: 30, left: 0, right: 0, child: ToastWidget()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoFeedLayout(BuildContext context, RoomContext roomCtx, DeviceScreenType deviceScreenType) {
    return Row(
      children: [
        /// show chat widget on mobile
        (deviceScreenType == DeviceScreenType.mobile && roomCtx.isChatEnabled)
            ? Expanded(child: _buildChatWidget(roomCtx))
            : Expanded(flex: 6, child: _buildMainVideoArea(roomCtx)),

        /// show chat widget on desktop
        (deviceScreenType != DeviceScreenType.mobile && roomCtx.isChatEnabled)
            ? Expanded(flex: 2, child: SizedBox(width: 400, child: _buildChatWidget(roomCtx)))
            : const SizedBox(width: 0, height: 0),
      ],
    );
  }

  Widget _buildChatWidget(RoomContext roomCtx) {
    return ChatBuilder(
      builder: (context, enabled, chatCtx, messages) {
        return ChatWidget(
          messages: messages,
          onSend: (message) => chatCtx.sendMessage(message),
          onClose: () {
            chatCtx.toggleChat(false);
          },
        );
      },
    );
  }

  Widget _buildMainVideoArea(RoomContext roomCtx) {
    return Stack(
      children: <Widget>[
        /// show participant loop
        ParticipantLoop(
          showAudioTracks: true,
          showVideoTracks: true,
          showParticipantPlaceholder: true,

          /// layout builder
          layoutBuilder: roomCtx.pinnedTracks.isNotEmpty ? const CarouselLayoutBuilder() : const GridLayoutBuilder(),

          /// participant builder
          participantTrackBuilder: (context, identifier) {
            return _buildParticipantTile(context, identifier, roomCtx);
          },
        ),

        /// show control bar at the bottom
        const Positioned(bottom: 30, left: 0, right: 0, child: ControlBar()),
      ],
    );
  }

  Widget _buildParticipantTile(BuildContext context, identifier, RoomContext roomCtx) {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Stack(
        children: [
          /// video track widget in the background
          identifier.isAudio && roomCtx.enableAudioVisulizer
              ? const AudioVisualizerWidget(backgroundColor: LKColors.lkDarkBlue)
              : IsSpeakingIndicator(
                builder: (context, isSpeaking) {
                  return isSpeaking != null
                      ? IsSpeakingIndicatorWidget(isSpeaking: isSpeaking, child: const VideoTrackWidget())
                      : const VideoTrackWidget();
                },
              ),

          /// focus toggle button at the top right
          const Positioned(top: 0, right: 0, child: FocusToggle()),

          /// track stats at the top left
          const Positioned(top: 8, left: 0, child: TrackStatsWidget()),

          /// status bar at the bottom
          const Positioned(bottom: 0, left: 0, right: 0, child: ParticipantStatusBar()),
        ],
      ),
    );
  }
}
