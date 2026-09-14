enum CasaShareMode {
  home,
  moon,
  all;

  String get label {
    switch (this) {
      case CasaShareMode.home:
        return 'honoo e hinoo di casa';
      case CasaShareMode.moon:
        return 'honoo e hinoo dalla luna';
      case CasaShareMode.all:
        return 'tutto';
    }
  }

  String get dbValue {
    switch (this) {
      case CasaShareMode.home:
        return 'home';
      case CasaShareMode.moon:
        return 'moon';
      case CasaShareMode.all:
        return 'all';
    }
  }

  static CasaShareMode? fromDb(String? value) {
    switch (value) {
      case 'home':
        return CasaShareMode.home;
      case 'moon':
        return CasaShareMode.moon;
      case 'all':
        return CasaShareMode.all;
      default:
        return null;
    }
  }
}

/// Filtri di visualizzazione dello Scrigno aperto dalla propria casa.
///
/// Sono distinti da [CasaShareMode] perché regolano soltanto la visualizzazione
/// dello Scrigno aperto dalla propria casa.
enum CasaChestFilter {
  authored,
  moonSaved,
  all;

  String get label {
    switch (this) {
      case CasaChestFilter.authored:
        return 'honoo e hinoo scritti da te';
      case CasaChestFilter.moonSaved:
        return 'honoo e hinoo salvati dalla luna';
      case CasaChestFilter.all:
        return 'tutto';
    }
  }
}
