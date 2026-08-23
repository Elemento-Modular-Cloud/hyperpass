import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Picture-of-the-day feed image (Electros `BackgroundImageData`).
@immutable
class PotdImage {
  const PotdImage({
    required this.imgUrl,
    this.title,
    this.thumbUrl,
    this.description,
  });

  final String imgUrl;
  final String? title;
  final String? thumbUrl;
  final String? description;
}

/// Electros `BackgroundProvider` frontend descriptor.
@immutable
class BackgroundProviderInfo {
  const BackgroundProviderInfo({
    required this.reference,
    required this.name,
    required this.icon,
  });

  final String reference;
  final String name;
  final IconData icon;
}

/// Feed-backed POTD providers (mirrors Electros `BackgroundProviders.json`).
class BackgroundProviderService {
  static const providers = <BackgroundProviderInfo>[
    BackgroundProviderInfo(
      reference: 'wikimedia',
      name: 'Wikimedia POTD',
      icon: Icons.public,
    ),
    BackgroundProviderInfo(
      reference: 'bing',
      name: 'Bing POTD',
      icon: Icons.image_outlined,
    ),
    BackgroundProviderInfo(
      reference: 'nasa',
      name: 'NASA POTD',
      icon: Icons.rocket_launch_outlined,
    ),
  ];

  static BackgroundProviderInfo? infoFor(String reference) {
    for (final provider in providers) {
      if (provider.reference == reference) return provider;
    }
    return null;
  }

  static Future<PotdImage?> fetchLatest(String reference) async {
    return switch (reference) {
      'bing' => _fetchBing(),
      'wikimedia' => _fetchWikimedia(),
      'nasa' => _fetchNasa(),
      _ => null,
    };
  }

  static Future<PotdImage?> _fetchBing() async {
    final response = await http.get(
      Uri.parse('https://peapix.com/bing/feed?country=us&n=1'),
    );
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data is! List || data.isEmpty) return null;
    final item = data.first as Map<String, dynamic>;
    final url = item['imageUrl'] as String?;
    if (url == null || url.isEmpty) return null;
    return PotdImage(
      imgUrl: url,
      title: item['title'] as String?,
      thumbUrl: item['thumbUrl'] as String?,
    );
  }

  static Future<PotdImage?> _fetchWikimedia() async {
    final response = await http.get(
      Uri.parse(
        'https://commons.wikimedia.org/w/api.php'
        '?action=featuredfeed&feed=potd&feedformat=atom&language=en',
      ),
    );
    if (response.statusCode != 200) return null;
    final document = XmlDocument.parse(response.body);
    final entry = document.findAllElements('entry').firstOrNull;
    if (entry == null) return null;

    final title = entry.getElement('title')?.innerText.trim();
    final summary = entry.getElement('summary')?.innerText ?? '';
    final srcsetMatch =
        RegExp(r'srcset="([^"]+)"').firstMatch(summary) ??
            RegExp(r"srcset='([^']+)'").firstMatch(summary);
    var url = srcsetMatch?.group(1)?.split(RegExp(r'\s+')).first;
    if (url == null || url.isEmpty) {
      final srcMatch = RegExp(r'src="([^"]+)"').firstMatch(summary);
      url = srcMatch?.group(1);
    }
    if (url == null || url.isEmpty) return null;

    if (url.contains('/thumb/')) {
      url = url
          .replaceFirst('/thumb/', '/')
          .replaceAll(RegExp(r'/[^/]+$'), '');
    }

    return PotdImage(
      imgUrl: url,
      title: title,
      thumbUrl: url,
    );
  }

  static Future<PotdImage?> _fetchNasa() async {
    final response = await http.get(Uri.parse('https://apod.com/feed.rss'));
    if (response.statusCode != 200) return null;
    final document = XmlDocument.parse(response.body);
    final item = document.findAllElements('item').firstOrNull;
    if (item == null) return null;

    final enclosure = item.findElements('enclosure').firstOrNull;
    final url = enclosure?.getAttribute('url');
    if (url == null || url.isEmpty) return null;

    return PotdImage(
      imgUrl: url,
      title: item.getElement('title')?.innerText.trim(),
      description: item.getElement('description')?.innerText.trim(),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
