import 'package:collection/collection.dart';

import '../distro_branding.dart';
import '../grpc_client.dart';
import '../l10n/app_localizations.dart';

int compareReleasesDescending(ImageInfo a, ImageInfo b) {
  final aNum = int.tryParse(a.release) ?? int.tryParse(a.codename);
  final bNum = int.tryParse(b.release) ?? int.tryParse(b.codename);
  if (aNum != null && bNum != null) {
    return bNum.compareTo(aNum);
  }
  return b.release.compareTo(a.release);
}

List<ImageInfo> sortImages(List<ImageInfo> images) {
  final mutable = List<ImageInfo>.from(images);

  final ltsIndex = mutable.indexWhere((image) {
    return image.aliases.any((alias) => alias == 'lts');
  });
  final lts = ltsIndex != -1 ? mutable.removeAt(ltsIndex) : null;

  final develIndex = mutable.indexWhere((image) {
    return image.aliases.any((alias) => alias == 'devel');
  });
  final devel = develIndex != -1 ? mutable.removeAt(develIndex) : null;

  bool coreFilter(ImageInfo image) {
    return image.aliases.any((alias) => alias.contains('core'));
  }

  bool ubuntuFilter(ImageInfo image) {
    return image.os.toLowerCase() == 'ubuntu';
  }

  final ubuntuImages = mutable
      .whereNot(coreFilter)
      .where(ubuntuFilter)
      .sorted(compareReleasesDescending);
  final coreImages = mutable.where(coreFilter).sorted(compareReleasesDescending);
  final thirdPartyImages = mutable
      .whereNot(coreFilter)
      .whereNot(ubuntuFilter)
      .sorted(compareReleasesDescending);

  return [
    if (lts != null) lts,
    ...ubuntuImages,
    if (devel != null) devel,
    ...coreImages,
    ...thirdPartyImages,
  ];
}

/// One row in the catalogue: a distro family with selectable releases.
class CatalogueEntry {
  const CatalogueEntry({
    required this.key,
    required this.defaultImage,
    required this.versions,
  });

  final String key;
  final ImageInfo defaultImage;
  final List<ImageInfo> versions;

  ImageInfo get representative => defaultImage;

  bool get isCore =>
      defaultImage.aliases.any((alias) => alias.contains('core'));

  String displayTitle(AppLocalizations l10n) =>
      _catalogueTitle(defaultImage, l10n);

  String description(AppLocalizations l10n) =>
      _catalogueDescription(defaultImage, l10n);

  bool matchesQuery(String query) {
    if (query.isEmpty) return true;
    final haystack = [
      defaultImage.os,
      displayTitleForSearch(),
      ...versions.map((v) => v.release),
      ...versions.map((v) => v.codename),
      ...versions.expand((v) => v.aliases),
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  String displayTitleForSearch() => distroBranding(defaultImage.os).displayName;
}

String _catalogueTitle(ImageInfo image, AppLocalizations l10n) {
  return switch (image.os.toLowerCase()) {
    'ubuntu' when image.aliases.any((a) => a.contains('core')) =>
      l10n.imageCardTitleUbuntuCore,
    'ubuntu' => l10n.imageCardTitleUbuntuServer,
    'debian' => l10n.imageCardTitleDebian,
    'fedora' => l10n.imageCardTitleFedora,
    'almalinux' => l10n.imageCardTitleAlmalinux,
    'rocky' => l10n.imageCardTitleRocky,
    'opensuse' => l10n.imageCardTitleOpensuse,
    'centos' => l10n.imageCardTitleCentos,
    'oraclelinux' => l10n.imageCardTitleOraclelinux,
    'arch' => l10n.imageCardTitleArch,
    'alpine' => l10n.imageCardTitleAlpine,
    'amazonlinux' => l10n.imageCardTitleAmazonlinux,
    _ => image.os,
  };
}

String _catalogueDescription(ImageInfo image, AppLocalizations l10n) {
  return switch (image.os.toLowerCase()) {
    'ubuntu' when image.aliases.any((a) => a.contains('core')) =>
      l10n.imageCardDescUbuntuCore,
    'ubuntu' => l10n.imageCardDescUbuntuServer,
    'debian' => l10n.imageCardDescDebian,
    'fedora' => l10n.imageCardDescFedora,
    'almalinux' => l10n.imageCardDescAlmalinux,
    'rocky' => l10n.imageCardDescRocky,
    'opensuse' => l10n.imageCardDescOpensuse,
    'centos' => l10n.imageCardDescCentos,
    'oraclelinux' => l10n.imageCardDescOraclelinux,
    'arch' => l10n.imageCardDescArch,
    'alpine' => l10n.imageCardDescAlpine,
    'amazonlinux' => l10n.imageCardDescAmazonlinux,
    _ => '',
  };
}

String catalogueVersionLabel(ImageInfo version) {
  return version.release.toLowerCase() == version.codename.toLowerCase()
      ? version.release
      : '${version.release} (${version.codename})';
}

bool catalogueVersionIsLts(ImageInfo version) =>
    version.aliases.any((alias) => alias == 'lts');

bool catalogueVersionIsDevel(ImageInfo version) =>
    version.aliases.any((alias) => alias == 'devel');

List<CatalogueEntry> groupCatalogueEntries(List<ImageInfo> images) {
  bool isCore(ImageInfo image) =>
      image.aliases.any((alias) => alias.contains('core'));

  bool isUbuntu(ImageInfo image) => image.os.toLowerCase() == 'ubuntu';

  bool isOther(ImageInfo image) => !isCore(image) && !isUbuntu(image);

  final ubuntuImages = images
      .where((image) => isUbuntu(image) && !isCore(image))
      .sorted(compareReleasesDescending)
      .toList();

  final coreImages = images
      .where((image) => isUbuntu(image) && isCore(image))
      .sorted(compareReleasesDescending)
      .toList();

  final otherByOs = groupBy(
    images.where(isOther),
    (ImageInfo image) => image.os.toLowerCase(),
  );

  final entries = <CatalogueEntry>[];

  if (ubuntuImages.isNotEmpty) {
    entries.add(
      CatalogueEntry(
        key: 'ubuntu',
        defaultImage: ubuntuImages.firstWhere(
          (image) => image.aliases.any((alias) => alias == 'lts'),
          orElse: () => ubuntuImages.first,
        ),
        versions: ubuntuImages,
      ),
    );
  }

  if (coreImages.isNotEmpty) {
    entries.add(
      CatalogueEntry(
        key: 'ubuntu-core',
        defaultImage: coreImages.first,
        versions: coreImages,
      ),
    );
  }

  for (final group in otherByOs.values) {
    final versions = group.sorted(compareReleasesDescending).toList();
    entries.add(
      CatalogueEntry(
        key: versions.first.os.toLowerCase(),
        defaultImage: versions.first,
        versions: versions,
      ),
    );
  }

  return entries;
}
