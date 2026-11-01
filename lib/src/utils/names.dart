// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A namespace for all the parameter names.
extension ParameterNames on Never {
  static const applyFixes = 'applyFixes';
  static const apps = 'apps';
  static const appUri = 'appUri';
  static const arguments = 'arguments';
  static const column = 'column';
  static const command = 'command';
  static const device = 'device';
  static const directory = 'directory';
  static const dtdUri = 'dtdUri';
  static const empty = 'empty';
  static const enabled = 'enabled';
  static const isolateId = 'isolateId';
  static const line = 'line';
  static const lines = 'lines';
  static const method = 'method';
  static const name = 'name';
  static const packageNames = 'packageNames';
  static const paths = 'paths';
  static const pid = 'pid';
  static const platform = 'platform';
  static const position = 'position';
  static const projectType = 'projectType';
  static const query = 'query';
  static const ready = 'ready';
  static const root = 'root';
  static const roots = 'roots';
  static const searchDir = 'searchDir';
  static const target = 'target';
  static const template = 'template';
  static const timeout = 'timeout';
  static const uri = 'uri';
  static const uris = 'uris';
  static const userJourney = 'user_journey';
  static const webLaunchUri = 'webLaunchUri';
}

/// The names of all the tools provided by the server.
enum ToolNames {
  analyzeFiles('analyze_files'),
  createProject('create_project'),
  dartFix('dart_fix'),
  dartFormat('dart_format'),
  dartpubSearch('dartpub_search'),
  dnAnalyze('dn_analyze'),
  dnAppLogs('dn_app_logs'),
  dnBuild('dn_build'),
  dnClean('dn_clean'),
  dnDevices('dn_devices'),
  dnDoctor('dn_doctor'),
  dnInstall('dn_install'),
  dnRun('dn_run'),
  dnStopApp('dn_stop_app'),
  dtd('dtd'),
  getActiveLocation('get_active_location'),
  getRuntimeErrors('get_runtime_errors'),
  hotReload('hot_reload'),
  hotRestart('hot_restart'),
  lsp('lsp'),
  pub('pub'),
  pubDevSearch('pub_dev_search'),
  readPackageUris('read_package_uris'),
  ripGrepPackages('rip_grep_packages'),
  roots('roots'),
  runTests('run_tests'),
  vmService('vm_service');

  final String name;
  const ToolNames(this.name);

  @override
  String toString() => name;
}
