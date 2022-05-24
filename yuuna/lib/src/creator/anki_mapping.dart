import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:yuuna/creator.dart';
import 'package:yuuna/models.dart';
import 'package:yuuna/utils.dart';

part 'anki_mapping.g.dart';

/// A user-generated mapping to allow customisation of the fields exported from
/// the application. A mapping is bound to a [model], which must have a length
/// of fields equal or more than the length of [getFields].
@JsonSerializable()
@Collection()
class AnkiMapping {
  /// Initialise a model mapping with the given parameters.
  AnkiMapping({
    required this.label,
    required this.model,
    required this.fieldKeys,
    required this.order,
    required this.tags,
    required this.enhancements,
    required this.actions,
    this.id,
  });

  /// Get the default mapping that is included with the application at first
  /// startup.
  factory AnkiMapping.defaultMapping(int order) {
    return AnkiMapping(
      label: standardProfileName,
      model: standardModelName,
      fieldKeys: [
        SentenceField.key,
        TermField.key,
        ReadingField.key,
        MeaningField.key,
        NotesField.key,
        ImageField.key,
        AudioField.key,
        ContextField.key,
      ],
      order: order,
      tags: [standardModelName],
      enhancements: defaultEnhancements,
      actions: defaultActions,
    );
  }

  /// A default map of enhancements to use for new mappings.
  static const Map<String, Map<int, String>> defaultEnhancements = {
    SentenceField.key: {0: ClearFieldEnhancement.key},
    TermField.key: {0: ClearFieldEnhancement.key},
    ReadingField.key: {0: ClearFieldEnhancement.key},
    MeaningField.key: {0: ClearFieldEnhancement.key},
    NotesField.key: {0: ClearFieldEnhancement.key},
    ImageField.key: {0: ClearFieldEnhancement.key},
    AudioField.key: {0: ClearFieldEnhancement.key},
  };

  /// A default map of enhancements to use for new mappings.
  static const Map<int, String> defaultActions = {0: CardCreatorAction.key};

  /// The default mapping name which cannot be deleted or reused.
  static String standardModelName = 'jidoujisho Yuuna';

  /// The default mapping name which cannot be deleted or reused.
  static String standardProfileName = 'Standard';

  /// A unique identifier for the purposes of database storage.
  @Id()
  int? id;

  /// The name of this mapping.
  @Index(unique: true)
  final String label;

  /// The name of the model to use when exporting with this mapping.
  final String model;

  /// Returns the unique key equivalents of the field in [getFields] that can
  /// be stored in a database.
  List<String?> fieldKeys;

  /// A collection of tags to always include when exporting with this mapping.
  final List<String> tags;

  /// Used to keep track of actions used in dictionary results.
  @QuickActionsConverter()
  final Map<int, String> actions;

  /// Used to keep track of enhancements used in the creator per field.
  @EnhancementsConverter()
  final Map<String, Map<int, String>> enhancements;

  /// Reserved index for the auto mode field in the map of enhancement names
  /// for a field.
  static int autoModeSlotNumber = -1;

  /// The order of this dictionary in terms of user sorting, relative to other
  /// dictionaries.
  @Index(unique: true)
  int order;

  /// The ordering of the fields to use when exporting with this mapping. The
  /// length of this must be less or equal the length of the model being used
  /// for export to work correctly.
  List<Field?> getFields() {
    List<Field?> fields = [];

    for (String? key in fieldKeys) {
      if (key == null) {
        fields.add(null);
      } else {
        Field field = fieldsByKey[key]!;
        fields.add(field);
      }
    }

    return fields;
  }

  /// Creates a deep copy of this mapping but with the given variables replaced
  /// with the new values.
  AnkiMapping copyWith({
    String? label,
    String? model,
    List<String?>? fieldKeys,
    List<String>? tags,
    int? order,
    int? id,
    Map<String, Map<int, String>>? enhancements,
    Map<int, String>? actions,
  }) {
    return AnkiMapping(
      label: label ?? this.label,
      model: model ?? this.model,
      fieldKeys: fieldKeys ?? this.fieldKeys,
      tags: tags ?? this.tags,
      order: order ?? this.order,
      id: id ?? this.id,
      enhancements: enhancements ?? this.enhancements,
      actions: actions ?? this.actions,
    );
  }

  /// Returns a list of enhancement names active for a certain field in the
  /// persisted enhancements map.
  List<String> getManualFieldEnhancementNames({required Field field}) {
    return enhancements[field]!
        .entries
        .where((entry) => entry.key != autoModeSlotNumber)
        .map((entry) => entry.value)
        .toList();
  }

  /// Returns the enhancement names active for a certain field in the persisted
  /// enhancements map.
  String? getAutoFieldEnhancementName({required Field field}) {
    return enhancements[field]![autoModeSlotNumber];
  }

  /// Returns a list of action names active in the persisted actions map.
  List<String> getActionNames() {
    return actions.values.toList();
  }

  /// Returns a list of enhancements active for a certain field in the
  /// persisted enhancements map.
  List<Enhancement> getManualFieldEnhancement(
      {required AppModel appModel, required Field field}) {
    List<String> enhancementNames =
        getManualFieldEnhancementNames(field: field);
    List<Enhancement> enhancements = enhancementNames
        .map((enhancementName) =>
            appModel.enhancements[field]![enhancementName]!)
        .toList();

    return enhancements;
  }

  /// Returns the enhancement active for a certain field in the persisted
  /// enhancements map.
  Enhancement? getAutoFieldEnhancement(
      {required AppModel appModel, required Field field}) {
    String? enhancementName = enhancements[field]![autoModeSlotNumber];
    if (enhancementName == null) {
      return null;
    }

    Enhancement? enhancement = appModel.enhancements[field]![enhancementName];
    return enhancement;
  }

  /// Returns a list of actions active for the persisted actions map.
  List<QuickAction> getActions({required AppModel appModel}) {
    List<String> actionNames = getActionNames();
    List<QuickAction> actions = actionNames
        .map((enhancementName) => appModel.quickActions[enhancementName]!)
        .toList();

    return actions;
  }
}
