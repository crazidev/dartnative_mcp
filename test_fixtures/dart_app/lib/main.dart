// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A simple class used by the ripgrep tests.
class Greeter {
  const Greeter(this.name);

  final String name;

  String greet() => 'Hello, $name!';
}

void main() {
  print(const Greeter('DartNative').greet());
}
