/// Lightweight lazy singleton registry (replaces GetX DI).
class ServiceLocator {
  ServiceLocator._();
  static final ServiceLocator I = ServiceLocator._();

  final Map<Type, Object Function()> _factories = {};
  final Map<Type, Object> _singletons = {};

  void lazy<T>(T Function() factory) {
    _factories[T] = factory as Object Function();
  }

  void register<T>(T instance) {
    _singletons[T] = instance as Object;
  }

  bool has<T>() => _singletons.containsKey(T) || _factories.containsKey(T);

  T get<T>() {
    final cached = _singletons[T];
    if (cached != null) return cached as T;

    final factory = _factories[T];
    if (factory == null) {
      throw StateError('Service $T is not registered');
    }
    final instance = factory() as T;
    _singletons[T] = instance as Object;
    return instance;
  }

  void reset<T>() {
    _singletons.remove(T);
  }

  void clear() {
    _singletons.clear();
    _factories.clear();
  }
}
