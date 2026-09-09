import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'download_manager.dart';
import '../models/song.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  // Miscellaneous innertube player client (VISIONOS), payload copied from
  // yt-dlp. Proven in the lab to be the ONLY client that yields media URLs
  // which serve 206 reliably for the problematic video: 39 streams, audio at
  // itag 140, `c=VISIONOS` and NO `n`/`pot` params (no JS deciphering needed).
  // The library's own ANDROID/SDKless URLs intermittently returned 403/416,
  // and ios/safari/tv manifest extraction fails for those videos.
  static const _visionosClient = YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
            '(KHTML, like Gecko) Version/26.0 Safari/605.1.15',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
      },
    },
  }, 'https://www.youtube.com/youtubei/v1/player?key=AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc&prettyPrint=false');

  // Multiple clients are tried because a single android client often yields
  // googlevideo URLs that fail at media-GET time. Deno-based JS solving is not
  // available on Android, so we rely on clients that do not (or rarely) require
  // signature/n decoding. `tv` is the library's own fallback for restricted
  // videos - keep it in the list (explicit lists skip the automatic fallback).
  static final List<YoutubeApiClient> _manifestClients = [
    _visionosClient,
    YoutubeApiClient.androidSdkless,
    YoutubeApiClient.ios,
    YoutubeApiClient.androidVr,
    YoutubeApiClient.safari,
    YoutubeApiClient.tv,
  ];

  // Watchdog: if no event (response header / body byte) arrives within this
  // window the transfer is considered dead. This is the FIRST-BYTE timeout -
  // it proves whether a response (and then body bytes) ever reached us.
  static const Duration _responseTimeout = Duration(seconds: 20);
  static const Duration _stallTimeout = Duration(seconds: 30);

  static const String _httpUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36';

  Future<StreamManifest> _getManifestFor(
          String videoId, YoutubeApiClient client) =>
      _yt.videos.streamsClient
          .getManifest(videoId, ytClients: [client]);

  Future<StreamManifest> _getManifestAll(String videoId) =>
      _yt.videos.streamsClient.getManifest(videoId, ytClients: _manifestClients);

  String _clientName(YoutubeApiClient client) =>
      client.payload['context']['client']['clientName'].toString();

  // Never expose the full signed googlevideo URL (query params carry the
  // signature/n token). Log host + path only.
  String _urlPreview(Uri url) => '${url.scheme}://${url.host}${url.path}';

  // Sanitized exception description: type + status code only. Raw exception
  // messages from this package embed the full signed request URL.
  String _describeException(Object e) {
    if (e is FatalFailureException) {
      return '${e.runtimeType} status=${e.statusCode}';
    }
    return e.runtimeType.toString();
  }

  Future<List<Song>> searchVideos(String query) async {
    final searchResult = await _yt.search.search(query);
    return searchResult.map((video) {
      return Song(
        id: video.id.value,
        title: video.title,
        author: video.author,
        duration: video.duration != null
            ? _formatDuration(video.duration!)
            : '0:00',
        thumbnailUrl: video.thumbnails.highResUrl,
      );
    }).toList();
  }

  AudioOnlyStreamInfo _bestAudioStream(AudioOnlyStreamInfo a,
      AudioOnlyStreamInfo b) {
    int score(AudioOnlyStreamInfo s) {
      var value = 0;
      if (s.fragments.isEmpty) value += 4;
      if (s.container.name == 'mp4') value += 2;
      return value;
    }

    final sa = score(a);
    final sb = score(b);
    if (sa != sb) return sa > sb ? a : b;
    if (a.bitrate.bitsPerSecond >= b.bitrate.bitsPerSecond) return a;
    return b;
  }

  AudioOnlyStreamInfo selectBestAudioStream(
      List<AudioOnlyStreamInfo> streams) {
    if (streams.isEmpty) {
      throw Exception('No audio streams available');
    }
    return streams.reduce(_bestAudioStream);
  }

  // Container name is directly usable as a file extension (per the library's
  // own docs). For an MP4 container decide m4a vs mp4 from the actual codec:
  // AAC audio in MP4 is conventionally .m4a; opus-in-mp4 stays .mp4.
  String _extForAudio(AudioOnlyStreamInfo s) {
    final name = s.container.name.toLowerCase();
    if (name != 'mp4') return name; // webm, 3gpp, ...
    final codecs = s.codec.parameters['codecs'] ?? '';
    return codecs.toLowerCase().contains('opus') ? 'mp4' : 'm4a';
  }

  Future<String> getAudioStreamUrl(String videoId) async {
    final manifest = await _getManifestAll(videoId);
    final audioStreams = manifest.audioOnly;
    if (audioStreams.isEmpty) {
      throw Exception('No audio streams available');
    }
    return selectBestAudioStream(audioStreams).url.toString();
  }

  Future<String> downloadAudio(Song song) async {
    debugPrint('[Download] START id=${song.id} title=${song.title}');
    Object? lastError;
    final appDir = await getApplicationDocumentsDirectory();

    for (final client in _manifestClients) {
      final name = _clientName(client);
      debugPrint('[Download] Client candidate=$name');
      debugPrint('[Download] Manifest requested (client=$name) id=${song.id}');

      late final StreamManifest manifest;
      try {
        manifest = await _getManifestFor(song.id, client);
      } catch (e, st) {
        debugPrint('[Download] Manifest FAILED (client=$name) '
            '${_describeException(e)}');
        debugPrint('$st');
        lastError = e;
        continue;
      }

      final audioStreams = manifest.audioOnly;
      debugPrint('[Download] Manifest received (client=$name) '
          'streams=${manifest.streams.length} audio=${audioStreams.length}');
      if (audioStreams.isEmpty) {
        debugPrint('[Download] NO_AUDIO_STREAMS (client=$name)');
        lastError = StateError('No audio streams for client $name');
        continue;
      }

      final audioInfo = selectBestAudioStream(audioStreams);
      final ext = _extForAudio(audioInfo);
      final filePath = '${appDir.path}/${song.id}.$ext';
      final codecs = audioInfo.codec.parameters['codecs'] ?? '';
      debugPrint('[Download] Stream selected tag=${audioInfo.tag} '
          'container=${audioInfo.container.name} '
          'codec=${audioInfo.codec.mimeType} codecs=$codecs '
          'fragmented=${audioInfo.fragments.isNotEmpty} '
          'totalBytes=${audioInfo.size.totalBytes} '
          'url=${_urlPreview(audioInfo.url)} target=$filePath');

      try {
        return await _downloadFrom(audioInfo, song, filePath);
      } catch (e, st) {
        debugPrint('[Download] Client candidate=$name FAILED: '
            '${_describeException(e)}');
        debugPrint('$st');
        lastError = e;
        continue;
      }
    }

    debugPrint('[Download] ALL_CLIENTS_FAILED');
    throw StateError(
        'All download candidates failed before producing bytes. '
        'Last: ${_describeException(lastError ?? StateError('unknown'))}');
  }

  // Transport: our own dart:io HttpClient CHUNKED ranged GET. This REPLACES
  // the library's streamsClient.get(), which was proven in the lab to silently
  // retry (403/FatalFailureException -> re-fetch manifest, other errors ->
  // up to 5 retries x recursive errorCount) yielding ZERO bytes with NO
  // surfaced error. Ranged GETs to googlevideo return 206 + body bytes; the
  // media servers were observed to answer chunked/partial ranges reliably
  // while rejecting full-file ANDROID-client requests (403/416). Chunked,
  // byte-resumable ranged download mirrors real media streaming, survives
  // mid-transfer failures, and every failure here becomes a visible,
  // bounded error.
  static const int _chunkBytes = 8 * 1024 * 1024;
  static const int _chunkRetries = 3;

  // Strip params that are signed-by-player but rejected by media servers when
  // stale or mismatched (same trick yt-dlp applies: remove n/pot/nsig/potoken).
  // `sig`/`lsig` are authoritative and MUST be kept.
  Uri _withoutSecurityParams(Uri url) {
    final params = <String, String>{
      for (final e in url.queryParameters.entries)
        if (!const {'n', 'pot', 'nsig', 'potoken', 'range'}.contains(e.key))
          e.key: e.value,
    };
    return url.replace(queryParameters: params);
  }

  // Sequentially downloads a contiguous set of byte-ranges of [streamUrl]
  // into [out] (RandomAccessFile). Returns the number of bytes written.
  // [onBytes] receives the absolute position in the output file so far.
  Future<int> _downloadRanges(
    HttpClient client,
    Uri url,
    RandomAccessFile out,
    int start,
    int endExclusive, {
    required void Function(int filePosition) onBytes,
  }) async {
    var position = start;
    var total = 0;
    while (position < endExclusive) {
      final chunkEnd =
          (position + _chunkBytes).clamp(1, endExclusive); // exclusive
      var received = -1;
      var lastErr = '';
      for (var attempt = 1; attempt <= _chunkRetries; attempt++) {
        try {
          final req = await client.getUrl(url);
          req.headers.set('user-agent', _httpUserAgent);
          req.headers.set('cookie', 'CONSENT=YES+cb');
          req.headers.set('Range', 'bytes=$position-${chunkEnd - 1}');
          debugPrint('[Download] REQUEST_RANGE $position-${chunkEnd - 1} '
              'attempt=$attempt');
          final resp = await req.close().timeout(_responseTimeout);
          if (resp.statusCode != 200 && resp.statusCode != 206) {
            throw HttpException('Media GET failed: HTTP ${resp.statusCode}');
          }
          received = 0;
          await out.setPosition(position);
          await for (final data in resp.timeout(_stallTimeout)) {
            await out.writeFrom(data);
            received += data.length;
            onBytes(position + received);
          }
          final expected = chunkEnd - position;
          if (received < expected) {
            throw StateError('Incomplete chunk: $received of $expected');
          }
          lastErr = '';
          break;
        } catch (e) {
          lastErr = _describeException(e);
          debugPrint('[Download] RANGE FAILED $position-${chunkEnd - 1} '
              'attempt=$attempt err=$lastErr');
          if (await out.position() != position) {
            try {
              await out.setPosition(position);
            } catch (_) {}
          }
        }
      }
      if (lastErr.isNotEmpty) {
        throw StateError('Chunk range $position-${chunkEnd - 1} failed '
            'after $_chunkRetries attempts: $lastErr');
      }
      debugPrint('[Download] RANGE COMPLETE $position-${chunkEnd - 1} '
          'bytes=$received');
      total += received;
      position = chunkEnd;
    }
    return total;
  }

  Future<String> _downloadFrom(
      AudioOnlyStreamInfo audioInfo, Song song, String filePath) async {
    final file = File(filePath);
    if (await file.exists() && await file.length() > 0) {
      debugPrint('[Download] ALREADY_EXISTS skip id=${song.id} '
          'size=${await file.length()}');
      return filePath;
    }

    final int totalBytes = audioInfo.size.totalBytes >= 0
        ? audioInfo.size.totalBytes
        : 0;
    final tempFile = File('$filePath.part');
    var downloadedBytes = 0;
    if (await tempFile.exists()) {
      downloadedBytes = (await tempFile.length());
      debugPrint('[Download] RESUME from existing .part size=$downloadedBytes');
    }

    final Uri url = _withoutSecurityParams(audioInfo.url);
    final int endExclusive = totalBytes > 0 ? totalBytes : 0;

    debugPrint('[Download] HTTP request starting '
        'url=${_urlPreview(url)} '
        'range=${totalBytes > 0 ? 'bytes=0-${totalBytes - 1}' : 'bytes=0-'} '
        'chunk=${_chunkBytes}B resume=$downloadedBytes');
    debugPrint('[Download] Waiting for FIRST CHUNK');
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    RandomAccessFile? out;

    try {
      out = await tempFile.open(mode: FileMode.append);
      if (endExclusive == 0 || downloadedBytes >= endExclusive) {
        // Unknown size (or already complete): single open-ended ranged GET.
        if (totalBytes == 0) {
          final req = await client.getUrl(url);
          req.headers.set('user-agent', _httpUserAgent);
          req.headers.set('cookie', 'CONSENT=YES+cb');
          req.headers.set('Range', 'bytes=0-');
          debugPrint('[Download] REQUEST_RANGE bytes=0- (unknown size)');
          final resp = await req.close().timeout(_responseTimeout);
          if (resp.statusCode != 200 && resp.statusCode != 206) {
            throw HttpException('Media GET failed: HTTP ${resp.statusCode}');
          }
          await out.setPosition(downloadedBytes == 0 ? 0 : downloadedBytes);
          await for (final data in resp.timeout(_stallTimeout)) {
            await out.writeFrom(data);
            downloadedBytes += data.length;
            debugPrint('[Download] CHUNK received length=${data.length} '
                'total=$downloadedBytes of unknown');
          }
        }
        if (totalBytes > 0 && downloadedBytes < totalBytes) {
          throw StateError(
              'Incomplete download: $downloadedBytes of $totalBytes');
        }
        if (downloadedBytes == 0) {
          throw HttpException('Media GET returned no bytes');
        }
      } else {
        var firstByteLogged = false;
        var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
        final added = await _downloadRanges(
          client,
          url,
          out,
          downloadedBytes,
          endExclusive,
          onBytes: (filePosition) {
            if (!firstByteLogged) {
              firstByteLogged = true;
              debugPrint('[Download] FIRST CHUNK received');
            }
            downloadedBytes = filePosition;
            final progress = downloadedBytes / totalBytes;
            debugPrint('[Download] PROGRESS=${progress.toStringAsFixed(4)} '
                'bytes=$downloadedBytes of $totalBytes');
            final now = DateTime.now();
            if (progress >= 1 ||
                now.difference(lastProgressAt) >=
                    const Duration(milliseconds: 200)) {
              lastProgressAt = now;
              unawaited(DownloadManager.instance
                  .updateProgress(song.id, song.title, progress));
            }
          },
        );
        if (added <= 0) {
          throw HttpException('Media download wrote no bytes');
        }
      }
      debugPrint('[Download] Stream consumption finished '
          'received=$downloadedBytes expected=$totalBytes');

      await out.flush();
      debugPrint('[Download] File flush completed');

      if (totalBytes > 0) {
        final actual = await tempFile.length();
        if (actual != totalBytes) {
          throw StateError(
              'Size mismatch: file=$actual expected=$totalBytes');
        }
      } else if (downloadedBytes == 0) {
        throw HttpException('Empty download');
      }

      await tempFile.rename(filePath);
      debugPrint('[Download] Rename .part -> final $filePath');

      final f = File(filePath);
      final size = await f.length();
      debugPrint('[Download] FINAL exists=${await f.exists()} size=$size '
          'expected=$totalBytes');
      await DownloadManager.instance.markCompleted(song.id);
      debugPrint('[Download] COMPLETE path=$filePath bytes=$downloadedBytes');
      return filePath;
    } catch (e, st) {
      debugPrint('[Download] ERROR type=${_describeException(e)} '
          'bytes=$downloadedBytes '
          'waiting=${downloadedBytes == 0 ? "FIRST_CHUNK" : "NEXT_CHUNK"}');
      if (e is TimeoutException) {
        debugPrint(downloadedBytes == 0
            ? '[Download] FIRST BYTE TIMEOUT'
            : '[Download] STALL TIMEOUT after $downloadedBytes bytes');
      }
      debugPrint('$st');
      final rs = out;
      if (rs != null) {
        try {
          await rs.flush();
        } catch (_) {}
        try {
          await rs.close();
        } catch (_) {}
      }
      client.close(force: true);
      // Partial bytes are intentionally KEPT for a future resume; only remove
      // an entry if nothing was written.
      if (downloadedBytes == 0 && await tempFile.exists()) {
        await tempFile.delete();
        debugPrint('[Download] DELETED empty .part $filePath.part');
      }
      DownloadManager.instance.remove(song.id);
      rethrow;
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void dispose() {
    _yt.close();
  }
}