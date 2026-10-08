import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:fastphoto/l10n/generated/app_localizations.dart';
import 'package:fastphoto/models/media_models.dart';
import 'package:fastphoto/models/app_settings.dart';

extension LocalizedContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension LocalizedAlbum on Album {
  String displayName(AppLocalizations strings) =>
      name.isEmpty ? strings.unnamedAlbum : name;
}

extension LocalizedPhoto on Photo {
  String displayAlbumName(AppLocalizations strings) =>
      albumName.isEmpty ? strings.otherPhotos : albumName;
}

extension LocalizedPlan on SortPlan {
  String displayName(AppLocalizations strings) => builtin
      ? strings.defaultPlan
      : (name.isEmpty ? strings.unnamedPlan : name);
}

String localizedMessage(AppLocalizations strings, String code) =>
    switch (code) {
      'photoPermissionBusy' => strings.photoPermissionBusy,
      'locationPermissionBusy' => strings.locationPermissionBusy,
      'nativeInvalidAlbumName' => strings.nativeInvalidAlbumName,
      'mediaOperationFailed' => strings.mediaOperationFailed,
      'photoReadFailed' => strings.photoReadFailed,
      'invalidPhotoUri' => strings.invalidPhotoUri,
      'locationPermissionRequired' => strings.locationPermissionRequired,
      'photoLocationReadFailed' => strings.photoLocationReadFailed,
      'photoUnavailable' => strings.photoUnavailable,
      'cannotReadPhoto' => strings.cannotReadPhoto,
      'transferBusy' => strings.transferBusy,
      'selectPhotosFirst' => strings.selectPhotosFirst,
      'unsupportedDestination' => strings.unsupportedDestination,
      'storageDisconnected' => strings.storageDisconnected,
      'crossVolumeMoveUnsupported' => strings.crossVolumeMoveUnsupported,
      'readFailed' => strings.readFailed,
      'copyFailed' => strings.copyFailed,
      'createDestinationFailed' => strings.createDestinationFailed,
      'writeDestinationFailed' => strings.writeDestinationFailed,
      'readOriginalFailed' => strings.readOriginalFailed,
      'finishCopyFailed' => strings.finishCopyFailed,
      'movePermissionFailed' => strings.movePermissionFailed,
      'systemMoveFailed' => strings.systemMoveFailed,
      'moveFailed' => strings.moveFailed,
      'operationIncomplete' => strings.operationIncomplete,
      'operationRetry' => strings.operationRetry,
      'settingsSaveFailed' => strings.settingsSaveFailed,
      'settingsLoadFailed' => strings.settingsLoadFailed,
      'unspecifiedReason' => strings.unspecifiedReason,
      'noPhotoLocation' => strings.noPhotoLocation,
      _ => strings.operationRetry,
    };

String photoDate(
  BuildContext context,
  DateTime date, {
  bool hideCurrentYear = false,
  bool includeTime = false,
}) {
  final locale = context.l10n.localeName;
  final format = hideCurrentYear && date.year == DateTime.now().year
      ? DateFormat.MMMd(locale)
      : DateFormat.yMMMd(locale);
  if (includeTime) format.add_Hm();
  return format.format(date);
}

String photoWeekday(BuildContext context, DateTime date) =>
    DateFormat.E(context.l10n.localeName).format(date);
