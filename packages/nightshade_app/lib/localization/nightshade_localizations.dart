import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

part 'nightshade_localizations/translations.dart';

class NightshadeLocalizations {
  final Locale locale;

  NightshadeLocalizations(this.locale);

  static const supportedLocales = [
    Locale('en'),
    Locale('es'),
  ];

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    _NightshadeLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static NightshadeLocalizations of(BuildContext context) {
    final localizations = Localizations.of<NightshadeLocalizations>(
      context,
      NightshadeLocalizations,
    );
    return localizations ?? NightshadeLocalizations(const Locale('en'));
  }

  String text(String key, {Map<String, String> params = const {}}) {
    final languageCode = _localizedValues.containsKey(locale.languageCode)
        ? locale.languageCode
        : 'en';
    var value = _localizedValues[languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
    params.forEach((paramKey, paramValue) {
      value = value.replaceAll('{$paramKey}', paramValue);
    });
    return value;
  }
}

class _NightshadeLocalizationsDelegate
    extends LocalizationsDelegate<NightshadeLocalizations> {
  const _NightshadeLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => NightshadeLocalizations.supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);

  @override
  Future<NightshadeLocalizations> load(Locale locale) async {
    return NightshadeLocalizations(locale);
  }

  @override
  bool shouldReload(_NightshadeLocalizationsDelegate old) => false;
}

extension NightshadeLocalizationsContext on BuildContext {
  NightshadeLocalizations get l10n => NightshadeLocalizations.of(this);
}
