// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// An interface class that provides a single getter of type [Sdk].
///
/// This provides information about the Dart and DartNative SDKs, if available.
abstract interface class SdkSupport {
  Sdk get sdk;
}

/// Information about the Dart and DartNative SDKs, if available.
class Sdk {
  /// The path to the root of the Dart SDK.
  final String? dartSdkPath;

  /// The path to the root of the DartNative SDK.
  ///
  /// This is the SDK that ships the `dn` executable.
  final String? dnSdkPath;

  /// Where [dartSdkPath] came from, for error messages, for example
  /// "the DART_ROOT environment variable".
  final String? dartSdkSource;

  /// Where [dnSdkPath] came from, for error messages.
  final String? dnSdkSource;

  Sdk({this.dartSdkPath, this.dnSdkPath, this.dartSdkSource, this.dnSdkSource});

  /// Creates an [Sdk] from the path to the Dart SDK.
  ///
  /// If no [dartSdkPath] is given, this will attempt to find one by
  /// first looking for a `DART_ROOT` environment variable, and then using
  /// [Platform.resolvedExecutable] (assuming that is the `dart` binary
  /// under the `bin` dir of a Dart SDK).
  ///
  /// Validates that the path is valid by checking for the `version` file.
  ///
  /// If no [dnSdkPath] is given, this will look at the `DN_ROOT` and
  /// `DARTNATIVE_ROOT` environment variables, then search up from the Dart SDK
  /// for a `bin/dn` executable.
  factory Sdk.find({
    String? dartSdkPath,
    String? dnSdkPath,
    Map<String, String>? environment,
  }) {
    environment ??= Platform.environment;
    String dartSdkSource;
    if (dartSdkPath != null) {
      dartSdkSource =
          'an explicitly given path (typically the --dart-sdk argument)';
    } else if (environment['DART_ROOT'] case final root?) {
      dartSdkPath = root;
      dartSdkSource = 'the DART_ROOT environment variable';
    } else if (environment['DART_SDK'] case final sdk?) {
      dartSdkPath = sdk;
      dartSdkSource = 'the DART_SDK environment variable';
    } else {
      // Assume that we are running from the Dart SDK bin dir if not given any
      // other configuration.
      dartSdkPath = p.dirname(p.dirname(Platform.resolvedExecutable));
      dartSdkSource =
          'the executable running the server '
          '(${Platform.resolvedExecutable})';
    }

    final versionFile = dartSdkPath.child('version');
    if (!File(versionFile).existsSync()) {
      throw ArgumentError('Invalid Dart SDK path: $dartSdkPath');
    }

    // Find the DartNative SDK (the SDK that ships `dn`).
    String? dnSdkSource;
    if (dnSdkPath != null) {
      dnSdkSource =
          'an explicitly given path (typically the --dn-sdk argument)';
    } else if (environment['DN_ROOT'] case final root?) {
      dnSdkPath = root;
      dnSdkSource = 'the DN_ROOT environment variable';
    } else if (environment['DARTNATIVE_ROOT'] case final root?) {
      dnSdkPath = root;
      dnSdkSource = 'the DARTNATIVE_ROOT environment variable';
    } else {
      // `dartSdkPath` is typically `<sdk>/bin/cache/dart-sdk`.
      final sdkRoot = dartSdkPath.parent.parent.parent;
      if (_hasDnExecutable(sdkRoot)) {
        dnSdkPath = sdkRoot;
        dnSdkSource = 'searching up from the Dart SDK';
      }
    }

    return Sdk(
      dartSdkPath: dartSdkPath,
      dnSdkPath: dnSdkPath,
      dartSdkSource: dartSdkSource,
      dnSdkSource: dnSdkSource,
    );
  }

  /// The path to the `dart` executable.
  ///
  /// Throws an [ArgumentError] if [dartSdkPath] is `null`.
  String get dartExecutablePath =>
      dartSdkPath
          ?.child('bin')
          .child('dart${Platform.isWindows ? '.exe' : ''}') ??
      (throw ArgumentError(
        'Dart SDK location unknown, try setting the DART_ROOT environment '
        'variable.',
      ));

  /// Whether a DartNative SDK (and therefore `dn`) is available.
  bool get hasDartNative => dnSdkPath != null;

  /// The path to the `dn` executable.
  ///
  /// Throws an [ArgumentError] if [dnSdkPath] is `null`.
  String get dnExecutablePath =>
      dnSdkPath?.child('bin').child('dn${Platform.isWindows ? '.bat' : ''}') ??
      (throw ArgumentError(_dnSdkUnknownMessage));

  String get _dnSdkUnknownMessage {
    final usingDart = switch ((dartSdkPath, dartSdkSource)) {
      (final path?, final source?) =>
        'The server is using the Dart SDK at $path, from $source. ',
      (final path?, null) => 'The server is using the Dart SDK at $path. ',
      _ => '',
    };
    return 'DartNative SDK location unknown. $usingDart'
        'To work on DartNative projects, start the server with '
        '`dn mcp-server`, pass --dn-sdk <path to the DartNative SDK>, or set '
        'the DN_ROOT environment variable.';
  }
}

bool _hasDnExecutable(String sdkRoot) => File(
  p.join(sdkRoot, 'bin', 'dn${Platform.isWindows ? '.bat' : ''}'),
).existsSync();

extension on String {
  String child(String path) => p.join(this, path);
  String get parent => p.dirname(this);
}
