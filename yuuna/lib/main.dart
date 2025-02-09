import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_to_file_image/network_to_file_image.dart';
import 'package:receive_intent/receive_intent.dart' as intents;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:spaces/spaces.dart';
import 'package:uri_to_file/uri_to_file.dart';
import 'package:wakelock/wakelock.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:yuuna/creator.dart';
import 'package:yuuna/media.dart';
import 'package:yuuna/models.dart';
import 'package:yuuna/pages.dart';
import 'package:yuuna/utils.dart';

/// Application execution starts here.
void main() {
  /// Run and handle an error zone to customise the action performed upon
  /// an error or exception. This allows for error logging for debug purposes
  /// as well as communicating errors to Crashlytics if enabled.
  runZonedGuarded<Future<void>>(() async {
    /// Necessary to initialise Flutter when running native code before
    /// starting the application.
    WidgetsFlutterBinding.ensureInitialized();

    /// Initialise Firebase to allow for Crashlytics error reporting.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    /// Allows the app to have configurable variables that can be changed on
    /// the fly without manual updates.
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: const Duration(hours: 1),
    ));

    /// Set default variables if there are none available from the server.
    await remoteConfig.setDefaults(const {
      'chatgpt_api_base_url': 'https://chat.openai.com/api',
      'chatgpt_backend_api_base_url': 'https://bypass.churchless.tech/api'
    });
    remoteConfig.fetchAndActivate();

    /// Ensure the top and bottom bars are shown at launch and wake prevention
    /// is disabled if not reverted from entering a media source.
    await Wakelock.disable();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    /// Used in order to access and initialise an [AppModel] without requiring
    /// a [WidgetRef].
    final container = ProviderContainer();
    final appModel = container.read(appProvider);
    await appModel.initialise();

    /// Start the application, specifying the [ProviderContainer] with the
    /// already initialised [AppModel].
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const JidoujishoApp(),
      ),
    );

    /// Pre-load and make the first user search faster.
    appModel.searchDictionary(
      searchTerm: appModel.targetLanguage.helloWorld,
      searchWithWildcards: false,
    );
  }, (exception, stack) {
    /// Print error details to the console.
    final details = FlutterErrorDetails(exception: exception, stack: stack);
    FlutterError.dumpErrorToConsole(details);

    /// Send error details to Crashlytics for developer debugging purposes.
    FirebaseCrashlytics.instance.recordError(exception, stack);
  });
}

/// Encapsulates theming, spacing and other configurable options pertaining to
/// the entire app, with some parameters dependent on the [AppModel].
class JidoujishoApp extends ConsumerStatefulWidget {
  /// Initialises an instance of the app.
  const JidoujishoApp({super.key});

  @override
  ConsumerState<JidoujishoApp> createState() => _JidoujishoAppState();
}

class _JidoujishoAppState extends ConsumerState<JidoujishoApp>
    with WidgetsBindingObserver {
  final navigatorKey = GlobalKey<NavigatorState>();
  bool _isMainIntent = false;

  late final StreamSubscription _intentsSubscription;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      /// Receive all intents and parse them depending on which they are.
      intents.ReceiveIntent.getInitialIntent().then(
        (intent) => handleIntent(
          intent: intent,
          isInitial: true,
        ),
      );
      // Attach a listener to the stream for receiving intents.
      _intentsSubscription = intents.ReceiveIntent.receivedIntentStream.listen(
        (intent) => handleIntent(
          intent: intent,
          isInitial: false,
        ),
      );
    });
  }

  @override
  void dispose() {
    _intentsSubscription.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void handleIntent({
    required intents.Intent? intent,
    required bool isInitial,
  }) async {
    if (intent == null) {
      return;
    }

    debugPrint(jsonEncode(intent.toMap()));

    switch (intent.action) {
      case 'android.intent.action.MAIN':
        setState(() {
          _isMainIntent = true;
        });
        return;
      case 'android.intent.action.SEND_MULTIPLE':
        List<String> contentUris =
            List<String>.from(intent.extra!['android.intent.extra.STREAM']);
        List<String> paths = [];
        for (int i = 0; i < contentUris.length; i++) {
          paths.add((await toFile(contentUris[i])).path);
        }

        imageShareIntentAction(paths);
        break;
      case 'android.intent.action.SEND':
        String? data = intent.extra!['android.intent.extra.TEXT'];
        if (data != null) {
          textShareIntentAction(data);
        } else {
          String contentUri = intent.extra!['android.intent.extra.STREAM'];
          String path = (await toFile(contentUri)).path;

          imageShareIntentAction([path]);
        }

        break;
      case 'android.intent.action.PROCESS_TEXT':
        String data = intent.extra!['android.intent.extra.PROCESS_TEXT'];
        textContextMenuAction(data);
        return;
      case 'android.intent.action.VIEW':
        String? subtitleUrl = intent.extra?['subtitles_location'];

        if (subtitleUrl == null) {
          if (intent.extra?['subs.enable'] != null) {
            try {
              List<String> subtitles =
                  List<String>.from(intent.extra?['subs.enable']);
              if (subtitles.isNotEmpty) {
                subtitleUrl = subtitles.first;
              }
            } finally {}
          }
        }
        String? title = intent.extra?['title'];
        int? position = intent.extra?['position'];
        if (position != null) {
          position = position ~/ 1000;
        }

        launchNetworkMediaAction(
          videoUrl: intent.data ?? '',
          extra: jsonEncode(intent.extra ?? {}),
          position: position,
          title: title,
        );
        return;
      case 'android.intent.action.WEB_SEARCH':
        String data = intent.extra!['query'];
        textContextMenuAction(data);
        return;
    }
  }

  void textContextMenuAction(String data) {
    if (data.trim().isNotEmpty) {
      appModel.openRecursiveDictionarySearch(
        searchTerm: data,
        killOnPop: true,
      );
    }
  }

  void textShareIntentAction(String data) {
    if (data.startsWith('https://') || data.startsWith('http://')) {
      String? videoId = VideoId.parseVideoId(data);
      if (videoId != null) {
        try {
          launchYoutubeMediaAction(data);
          return;
        } catch (e) {
          debugPrint('Not a YouTube video');
        }
      }

      if (data.toLowerCase().endsWith('.jpg') ||
          data.toLowerCase().endsWith('.jpeg') ||
          data.toLowerCase().endsWith('.png')) {
        appModel.openCreator(killOnPop: true, ref: ref);
        List<NetworkToFileImage> images = [NetworkToFileImage(url: data)];

        Future.delayed(const Duration(milliseconds: 100), () {
          ImageField.instance.setImages(
            appModel: appModel,
            creatorModel: creatorModel,
            cause: EnhancementTriggerCause.manual,
            newAutoCannotOverride: true,
            generateImages: () async {
              return images;
            },
          );
        });
      }
    } else {
      if (data.trim().isNotEmpty) {
        appModel.openCreator(
          creatorFieldValues: CreatorFieldValues(
            textValues: {
              SentenceField.instance: data,
            },
          ),
          killOnPop: true,
          ref: ref,
        );
      }
    }
  }

  void imageShareIntentAction(List<String> paths) {
    if (paths.isEmpty) {
      return;
    }

    appModel.openCreator(killOnPop: true, ref: ref);

    List<NetworkToFileImage> images = paths.map(
      (path) {
        return NetworkToFileImage(
          file: File(path),
        );
      },
    ).toList();

    Future.delayed(const Duration(milliseconds: 100), () {
      ImageField.instance.setImages(
        appModel: appModel,
        creatorModel: creatorModel,
        cause: EnhancementTriggerCause.manual,
        newAutoCannotOverride: true,
        generateImages: () async {
          return images;
        },
      );
    });
  }

  void launchYoutubeMediaAction(String url) async {
    MediaItem item =
        await PlayerYoutubeSource.instance.getMediaItemFromUrl(url);

    Navigator.popUntil(
        appModel.navigatorKey.currentContext!, (route) => route.isFirst);
    if (mounted) {
      await appModel.openMedia(
        context: context,
        ref: ref,
        mediaSource: PlayerYoutubeSource.instance,
        killOnPop: true,
        item: item,
      );
    }
  }

  void launchNetworkMediaAction({
    required String videoUrl,
    required String extra,
    int? position,
    String? title,
  }) async {
    MediaItem item = PlayerNetworkStreamSource.instance.getMediaItemFromUrl(
      videoUrl: videoUrl,
      extra: extra,
      position: position,
      title: title,
    );

    Navigator.popUntil(
        appModel.navigatorKey.currentContext!, (route) => route.isFirst);
    await appModel.openMedia(
      context: context,
      ref: ref,
      mediaSource: PlayerNetworkStreamSource.instance,
      killOnPop: true,
      item: item,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: appModel.navigatorKey,
      home: home,
      locale: locale,
      themeMode: themeMode,
      theme: appModel.theme,
      darkTheme: appModel.darkTheme,
      // This is responsible for the initialising the global spacing across
      // the entire project, making use of the [spaces] package.
      builder: (context, child) => Spacing(
        dataBuilder: (context) {
          return SpacingData.generate(10);
        },
        child: child!,
      ),
    );
  }

  /// Responsible for managing global app-wide state.
  AppModel get appModel => ref.watch(appProvider);

  /// Responsible for managing global app-wide state.
  CreatorModel get creatorModel => ref.watch(creatorProvider);

  /// The application will open to this page upon startup.
  Widget get home => _isMainIntent ? const HomePage() : const Scaffold();

  /// The current theme mode, which by default is based on system setting
  /// and toggleable.
  ThemeMode get themeMode =>
      appModel.isDarkMode ? ThemeMode.dark : ThemeMode.light;

  /// The current locale, dependent on the active target language.
  Locale get locale => appModel.targetLanguage.locale;
}
