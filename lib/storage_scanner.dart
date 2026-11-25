import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DuplicateGroup {
  final String hash;
  final int fileSizeBytes;
  final List<File> files;

  const DuplicateGroup({
    required this.hash,
    required this.fileSizeBytes,
    required this.files,
  });

  int get reclaimableBytes =>
      files.length > 1 ? fileSizeBytes * (files.length - 1) : 0;
}

class JunkScanResult {
  final List<File> tempFiles;
  final List<Directory> emptyDirs;
  final int totalJunkBytes;

  const JunkScanResult({
    required this.tempFiles,
    required this.emptyDirs,
    required this.totalJunkBytes,
  });
}

class StorageScanner {
  /// Returns scannable directories accessible to the app on Android.
  static Future<List<Directory>> getScannableRoots() async {
    final roots = <Directory>[];
    final candidates = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Documents',
      '/storage/emulated/0/Pictures',
    ];
    for (final path in candidates) {
      final dir = Directory(path);
      try {
        if (await dir.exists()) {
          await dir.list().take(1).toList();
          roots.add(dir);
        }
      } catch (_) {
        // Scoped storage restriction; skip gracefully
      }
    }

    // Always include app documents & temp directories so scan works out of the box
    final appDocs = await getApplicationDocumentsDirectory();
    final appCache = await getTemporaryDirectory();
    roots.add(appDocs);
    roots.add(appCache);
    return roots;
  }

  /// Finds exact duplicate files using fast size-grouping followed by SHA-256 hashing.
  static Future<List<DuplicateGroup>> findDuplicates({
    int maxFilesToScan = 1500,
  }) async {
    final roots = await getScannableRoots();
    final bySize = <int, List<File>>{};
    int scanned = 0;

    for (final root in roots) {
      if (scanned >= maxFilesToScan) break;
      try {
        await for (final entity in root.list(recursive: true, followLinks: false)) {
          if (scanned >= maxFilesToScan) break;
          if (entity is File) {
            try {
              final stat = await entity.stat();
              // Skip empty files and huge (>50MB) videos to keep scanning snappy
              if (stat.size > 0 && stat.size < 50 * 1024 * 1024) {
                bySize.putIfAbsent(stat.size, () => []).add(entity);
                scanned++;
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    final duplicateGroups = <DuplicateGroup>[];

    for (final entry in bySize.entries) {
      if (entry.value.length < 2) continue;
      final byHash = <String, List<File>>{};

      for (final file in entry.value) {
        try {
          final digest = await sha256.bind(file.openRead()).first;
          byHash.putIfAbsent(digest.toString(), () => []).add(file);
        } catch (_) {}
      }

      for (final hEntry in byHash.entries) {
        if (hEntry.value.length > 1) {
          duplicateGroups.add(
            DuplicateGroup(
              hash: hEntry.key,
              fileSizeBytes: entry.key,
              files: hEntry.value,
            ),
          );
        }
      }
    }

    duplicateGroups.sort(
      (a, b) => b.reclaimableBytes.compareTo(a.reclaimableBytes),
    );
    return duplicateGroups;
  }

  /// Scans for residual temporary files (.tmp, .log, .bak, .cache) and empty folders.
  static Future<JunkScanResult> scanResidualJunk() async {
    final roots = await getScannableRoots();
    final tempFiles = <File>[];
    final emptyDirs = <Directory>[];
    int totalBytes = 0;

    const junkExts = {'.tmp', '.temp', '.log', '.bak', '.old', '.cache'};

    for (final root in roots) {
      try {
        await for (final entity in root.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (junkExts.contains(ext)) {
              try {
                final len = await entity.length();
                tempFiles.add(entity);
                totalBytes += len;
              } catch (_) {}
            }
          } else if (entity is Directory) {
            try {
              final contents = await entity.list().take(1).toList();
              if (contents.isEmpty) {
                emptyDirs.add(entity);
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    return JunkScanResult(
      tempFiles: tempFiles,
      emptyDirs: emptyDirs,
      totalJunkBytes: totalBytes,
    );
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
