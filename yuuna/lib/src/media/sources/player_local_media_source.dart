import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:material_floating_search_bar/material_floating_search_bar.dart';
import 'package:yuuna/media.dart';
import 'package:yuuna/models.dart';
import 'package:yuuna/pages.dart';
import 'package:yuuna/utils.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:path/path.dart' as path;

/// A media source that allows the user to watch videos in their local device
/// storage.
class PlayerLocalMediaSource extends PlayerMediaSource {
  /// Define this media source.
  PlayerLocalMediaSource._privateConstructor()
      : super(
          uniqueKey: 'player_local_media',
          sourceName: 'Local Media',
          description: 'Play videos sourced from local device storage.',
          icon: Icons.storage,
          implementsSearch: false,
          implementsHistory: true,
        );

  /// Get the singleton instance of this media type.
  static PlayerLocalMediaSource get instance => _instance;

  static final PlayerLocalMediaSource _instance =
      PlayerLocalMediaSource._privateConstructor();

  @override
  List<Widget> getActions({
    required BuildContext context,
    required WidgetRef ref,
    required AppModel appModel,
  }) {
    return [
      buildPickVideoButton(
        context: context,
        ref: ref,
        appModel: appModel,
      ),
    ];
  }

  /// Allows user to pick a video file.
  Widget buildPickVideoButton({
    required BuildContext context,
    required WidgetRef ref,
    required AppModel appModel,
  }) {
    return FloatingSearchBarAction(
      showIfOpened: true,
      child: JidoujishoIconButton(
        size: Theme.of(context).textTheme.titleLarge?.fontSize,
        tooltip: t.pick_video_file,
        icon: Icons.perm_media,
        onTap: () => pickVideoFile(
          context: context,
          appModel: appModel,
          ref: ref,
          pushReplacement: false,
        ),
      ),
    );
  }

  @override
  Future<void> onSearchBarTap({
    required BuildContext context,
    required WidgetRef ref,
    required AppModel appModel,
  }) async {
    pickVideoFile(
      context: context,
      appModel: appModel,
      ref: ref,
      pushReplacement: false,
    );
  }

  /// Used to generate a thumbnail for a video file.
  Future<void> generateThumbnail(String inputPath, String targetPath) async {
    String timestamp =
        JidoujishoTimeFormat.getFfmpegTimestamp(const Duration(seconds: 30));
    final FlutterFFmpeg _flutterFFmpeg = FlutterFFmpeg();

    String command =
        '-ss $timestamp -y -i "$inputPath" -frames:v 1 -q:v 2 "$targetPath"';

    await _flutterFFmpeg.execute(command);
  }

  /// Pick a video file with a built-in file picker.
  Future<void> pickVideoFile({
    required BuildContext context,
    required AppModel appModel,
    required WidgetRef ref,
    required bool pushReplacement,
  }) async {
    List<Directory> rootDirectories =
        await appModel.getFilePickerDirectoriesForMediaType(mediaType);

    List<String> usedFiles = appModel
        .getMediaSourceHistory(mediaSource: this)
        .map((item) => item.mediaIdentifier)
        .toList();

    Iterable<String>? filePaths = await FilesystemPicker.open(
      allowedExtensions: allowedExtensions,
      context: context,
      rootDirectories: rootDirectories,
      fsType: FilesystemType.file,
      title: '',
      pickText: t.dialog_select,
      cancelText: t.dialog_cancel,
      themeData: Theme.of(context),
      folderIconColor: Theme.of(context).colorScheme.primary,
      usedFiles: usedFiles,
      currentActiveFile: appModel.currentMediaItem?.mediaIdentifier,
    );

    if (filePaths == null || filePaths.isEmpty) {
      return;
    }

    String filePath = filePaths.first;
    appModel.setLastPickedDirectory(
      type: PlayerMediaType.instance,
      directory: Directory(path.dirname(filePath)),
    );

    MediaItem? item = appModel
        .getMediaTypeHistory(mediaType: mediaType)
        .firstWhereOrNull((item) => item.mediaIdentifier == filePath);
    if (item == null) {
      item ??= MediaItem(
        canDelete: true,
        canEdit: false,
        mediaTypeIdentifier: mediaType.uniqueKey,
        mediaSourceIdentifier: uniqueKey,
        mediaIdentifier: filePath,
        position: 0,
        duration: 0,
        title: path.basenameWithoutExtension(filePath),
      );

      String thumbnailPath = appModel.getThumbnailFile().path;
      File thumbnailFile = appModel.getThumbnailFile();

      if (thumbnailFile.existsSync()) {
        thumbnailFile.deleteSync();
      }
      thumbnailFile.createSync(recursive: true);

      await generateThumbnail(filePath, thumbnailPath);
      await setOverrideThumbnailFromMediaItem(
        appModel: appModel,
        item: item,
        file: thumbnailFile,
      );
    }

    await appModel.openMedia(
      pushReplacement: pushReplacement,
      context: context,
      ref: ref,
      mediaSource: this,
      item: item,
    );
  }

  @override
  BaseSourcePage buildLaunchPage({
    MediaItem? item,
  }) {
    return PlayerSourcePage(
      item: item,
      source: this,
      useHistory: true,
    );
  }

  /// Used to filter the files found in a directory.
  List<String> allowedExtensions = const [
    '.3gp',
    '.aaf',
    '.asf',
    '.avchd',
    '.avi',
    '.drc',
    '.flv',
    '.m2v',
    '.m4p',
    '.m4v',
    '.mkv',
    '.mng',
    '.mov',
    '.mp2',
    '.mp4',
    '.mpe',
    '.mpeg',
    '.mpg',
    '.mpv',
    '.mxf',
    '.nsv',
    '.ogg',
    '.ogv',
    '.ogm',
    '.qt',
    '.rm',
    '.rmvb',
    '.svi',
    '.vob',
    '.webm',
    '.wmv',
    '.yuv'
  ];

  @override
  Future<VlcPlayerController> preparePlayerController({
    required AppModel appModel,
    required WidgetRef ref,
    required MediaItem item,
  }) async {
    int startTime = item.position;

    List<String> advancedParams = ['--start-time=$startTime'];
    List<String> audioParams = [
      '--audio-language=${appModel.targetLanguage.languageCode},${appModel.appLocale.languageCode}',
      '--sub-track=99999'
    ];

    return VlcPlayerController.file(
      File(item.mediaIdentifier),
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions(advancedParams),
        audio: VlcAudioOptions(audioParams),
      ),
    );
  }

  @override
  Future<List<SubtitleItem>> prepareSubtitles({
    required AppModel appModel,
    required WidgetRef ref,
    required MediaItem item,
  }) async {
    List<SubtitleItem> items = [];

    File videoFile = File(item.mediaIdentifier);
    Directory directory = Directory(path.dirname(videoFile.path));

    List<FileSystemEntity> entityList = directory.listSync();

    String videoFileBasename = path.basenameWithoutExtension(videoFile.path);

    List<FileSystemEntity> matchingEntities = entityList.where((entity) {
      return entity is File &&
          path.basename(entity.path).startsWith(videoFileBasename) &&
          (path.extension(entity.path).toLowerCase() == '.ass' ||
              path.extension(entity.path).toLowerCase() == '.srt') &&
          videoFile.path != entity.path;
    }).toList();

    for (FileSystemEntity file in matchingEntities) {
      if (file is File) {
        String metadata =
            path.basename(file.path).replaceAll(videoFileBasename, '');
        SubtitleItem? item = await SubtitleUtils.subtitlesFromFile(
          file: file,
          metadata: metadata,
          type: SubtitleItemType.externalSubtitle,
        );
        items.add(item);
      }
    }

    return items;
  }
}
