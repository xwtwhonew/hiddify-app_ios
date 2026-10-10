import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Makes the SOCKS5 proxy in [asset] the active profile, so a new install can
/// connect without the proxy being typed in.
///
/// Each set of values is applied once. Changes made to the profile in the app
/// stay until a build ships different values, which then replace them.
class DefaultProxyProfile with InfraLogger {
  DefaultProxyProfile({required this.repository, required this.sharedPreferences});

  final ProfileRepository repository;
  final SharedPreferences sharedPreferences;

  static const asset = "assets/config/default_proxy.json";
  static const appliedKey = "default_proxy_applied";
  static const profileIdKey = "default_proxy_profile_id";

  Future<void> apply() async {
    final proxy = jsonDecode(await rootBundle.loadString(asset)) as Map<String, dynamic>;
    final server = (proxy["server"] as String? ?? "").trim();
    if (server.isEmpty) {
      loggy.debug("no default proxy configured");
      return;
    }
    final name = proxy["name"] as String? ?? "SOCKS5";
    final username = proxy["username"] as String? ?? "";
    final password = proxy["password"] as String? ?? "";
    final content = jsonEncode({
      "outbounds": [
        {
          "type": "socks",
          "tag": name,
          "server": server,
          "server_port": int.tryParse("${proxy["port"]}") ?? 1080,
          "version": "5",
          if (username.isNotEmpty) "username": username,
          if (password.isNotEmpty) "password": password,
        },
      ],
    });
    if (sharedPreferences.getString(appliedKey) == content) return;

    final previousId = sharedPreferences.getString(profileIdKey);
    final previous = previousId == null ? null : (await repository.getById(previousId).run()).getOrElse((_) => null);
    final String id;
    if (previous != null) {
      id = previous.id;
      (await repository.offlineUpdate(previous, content).run()).getOrElse((failure) => throw failure);
    } else {
      id = const Uuid().v4();
      final added = await repository.addLocal(content, userOverride: UserOverride(name: name), profileId: id).run();
      added.getOrElse((failure) => throw failure);
    }
    (await repository.setAsActive(id).run()).getOrElse((failure) => throw failure);
    await sharedPreferences.setString(profileIdKey, id);
    await sharedPreferences.setString(appliedKey, content);
    loggy.info("default proxy profile [$name] applied");
  }
}
