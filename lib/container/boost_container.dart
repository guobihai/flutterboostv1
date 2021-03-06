/*
 * The MIT License (MIT)
 * 
 * Copyright (c) 2019 Alibaba Group
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'container_manager.dart';
import '../flutter_boost.dart';
import 'boost_page_route.dart';
import '../support/logger.dart';

enum ContainerLifeCycle {
  Init,
  Appear,
  WillDisappear,
  Disappear,
  Destroy,
  Background,
  Foreground
}

typedef void BoostContainerLifeCycleObserver(
    ContainerLifeCycle state, BoostContainerSettings settings);

class BoostContainer extends Navigator {
  final BoostContainerSettings settings;

  const BoostContainer(
      {GlobalKey<BoostContainerState> key,
      this.settings = const BoostContainerSettings(),
      String initialRoute,
      RouteFactory onGenerateRoute,
      RouteFactory onUnknownRoute,
      List<NavigatorObserver> observers})
      : super(
            key: key,
            initialRoute: initialRoute,
            onGenerateRoute: onGenerateRoute,
            onUnknownRoute: onUnknownRoute,
            observers: observers);

  factory BoostContainer.copy(Navigator navigator,
          [BoostContainerSettings settings = const BoostContainerSettings()]) =>
      BoostContainer(
        key: GlobalKey<BoostContainerState>(),
        settings: settings,
        initialRoute: navigator.initialRoute,
        onGenerateRoute: navigator.onGenerateRoute,
        onUnknownRoute: navigator.onUnknownRoute,
        observers: navigator.observers,
      );

  factory BoostContainer.obtain(
          Navigator navigator, BoostContainerSettings settings) =>
      BoostContainer(
          key: GlobalKey<BoostContainerState>(),
          settings: settings,
          onGenerateRoute: (RouteSettings routeSettings) {
            if (routeSettings.name == '/') {
              return BoostPageRoute<dynamic>(
                  pageName: settings.name,
                  params: settings.params,
                  uniqueId: settings.uniqueId,
                  animated: false,
                  settings: routeSettings,
                  builder: settings.builder);
            } else {
              return navigator.onGenerateRoute(routeSettings);
            }
          },
          observers: <NavigatorObserver>[
            ContainerNavigatorObserver.bindContainerManager()
          ],
          onUnknownRoute: navigator.onUnknownRoute);

  @override
  BoostContainerState createState() => BoostContainerState();

  @override
  StatefulElement createElement() => ContainerElement(this);

  static BoostContainerState tryOf(BuildContext context) {
    final BoostContainerState container =
        context.ancestorStateOfType(const TypeMatcher<BoostContainerState>());
    return container;
  }

  static BoostContainerState of(BuildContext context) {
    final BoostContainerState container =
        context.ancestorStateOfType(const TypeMatcher<BoostContainerState>());
    assert(container != null, 'not in flutter boost');
    return container;
  }

  String desc() => '{uniqueId=${settings.uniqueId},name=${settings.name}}';
}

class BoostContainerState extends NavigatorState {
  VoidCallback backPressedHandler;

  String get uniqueId => widget.settings.uniqueId;

  String get name => widget.settings.name;

  Map get params => widget.settings.params;

  BoostContainerSettings get settings => widget.settings;

  bool get onstage =>
      BoostContainerManager.of(context).onstageContainer == this;

  bool get maybeOnstageNext =>
      BoostContainerManager.of(context).subContainer == this;

  @override
  BoostContainer get widget => super.widget as BoostContainer;

  List<Route<dynamic>> routerHistory = <Route<dynamic>>[];

  bool multipleRouteMode = false;

  ContainerNavigatorObserver findContainerNavigatorObserver(
      Navigator navigator) {
    for (NavigatorObserver observer in navigator.observers) {
      if (observer is ContainerNavigatorObserver) {
        return observer;
      }
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    backPressedHandler = () => maybePop();
  }

  @override
  void didUpdateWidget(Navigator oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    for (Route route in routerHistory) {
      GlobalRouteSettingsManager.instance.removeSettings(route);
    }

    routerHistory.clear();

    super.dispose();
  }

  void performBackPressed() {
    Logger.log('performBackPressed');

    backPressedHandler?.call();
  }

  Route get topRoute => routerHistory.isNotEmpty ? routerHistory.last : null;

  @override
  Future<bool> maybePop<T extends Object>([T result]) async {
    if(routerHistory.isEmpty){
      pop(result);
      return true;
    }


    final Route<T> route = routerHistory.last;
    final RoutePopDisposition disposition = await route.willPop();
    if (mounted) {
      switch (disposition) {
        case RoutePopDisposition.pop:
          pop(result);
          return true;
          break;
        case RoutePopDisposition.doNotPop:
          return false;
          break;
        case RoutePopDisposition.bubble:
          pop(result);
          return true;
          break;
      }
    }
    return false;
  }

  @override
  bool pop<T extends Object>([T result]) {
    Route removedRoute;
    if (routerHistory.length >= 1) {
      removedRoute = routerHistory.removeLast();
    }

    if (canPop()) {
         super.pop<T>(result);
         if (removedRoute != null) {
           GlobalRouteSettingsManager.instance.removeSettings(removedRoute);
         }
         if (Platform.isIOS && multipleRouteMode && !canPop()) {
           FlutterBoost.singleton.channel
               .invokeMethod<dynamic>('enablePopGesture', null);
           //开启native返回手势
         }
    } else {
      if (T is Map<String, dynamic>) {
        FlutterBoost.singleton
            .closeInternal(uniqueId, result: result as Map<String, dynamic>);
      } else {
        FlutterBoost.singleton.closeInternal(uniqueId,);
      }
    }
    return true;
  }

  @override
  Future<T> push<T extends Object>(Route<T> route) {
    Route<T> newRoute;
    if (FlutterBoost.containerManager.prePushRoute != null) {
      newRoute = FlutterBoost.containerManager
          .prePushRoute(name, uniqueId, params, route);
    }

    if (multipleRouteMode) {
      ContainerNavigatorObserver.bindContainerManager().willPush(route, routerHistory.last);
    }

    Future<T> future = super.push<T>(newRoute ?? route);

    routerHistory.add(route);

    // 复用XPlatformPlugin后，每次进入页面时都需要在这里反复通知Native更新Theme
    SystemChrome.restoreSystemUIOverlays();
    if (FlutterBoost.containerManager.postPushRoute != null) {
      FlutterBoost.containerManager
          .postPushRoute(name, uniqueId, params, newRoute ?? route, future);
    }

    if (Platform.isIOS && multipleRouteMode && canPop()) {
      FlutterBoost.singleton.channel
          .invokeMethod<dynamic>('disablePopGesture', null);
    }

    return future;
  }

  VoidCallback addLifeCycleObserver(BoostContainerLifeCycleObserver observer) {
    return FlutterBoost.singleton.addBoostContainerLifeCycleObserver(
        (ContainerLifeCycle state, BoostContainerSettings settings) {
      if (settings.uniqueId == uniqueId) {
        observer(state, settings);
      }
    });
  }
}

class BoostContainerSettings {
  final String uniqueId;
  final String name;
  final Map params;
  final WidgetBuilder builder;

  const BoostContainerSettings(
      {this.uniqueId = 'default',
      this.name = 'default',
      this.params,
      this.builder});
}

class ContainerElement extends StatefulElement {
  ContainerElement(StatefulWidget widget) : super(widget);
}

class ContainerNavigatorObserver extends NavigatorObserver {
  static final Set<NavigatorObserver> boostObservers = Set<NavigatorObserver>();

  ContainerNavigatorObserver();

  factory ContainerNavigatorObserver.bindContainerManager() =>
      ContainerNavigatorObserver();

  VoidCallback addBoostNavigatorObserver(NavigatorObserver observer) {
    boostObservers.add(observer);

    return () => boostObservers.remove(observer);
  }

  void removeBoostNavigatorObserver(NavigatorObserver observer) {
    boostObservers.remove(observer);
  }

  void willPush(Route<dynamic> route, Route<dynamic> previousRoute) {
    for (NavigatorObserver observer in boostObservers) {
      if(observer is ContainerNavigatorObserver){
        if (observer == this) continue;
        ContainerNavigatorObserver  containerNavigatorObserver = observer as ContainerNavigatorObserver;
        containerNavigatorObserver.willPush(route, previousRoute);
      }
    }
  }
  @override
  void didPush(Route<dynamic> route, Route<dynamic> previousRoute) {
    for (NavigatorObserver observer in boostObservers) {
      if (observer == this) continue;
      observer.didPush(route, previousRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic> previousRoute) {
    for (NavigatorObserver observer in boostObservers) {
      if (observer == this) continue;
      observer.didPop(route, previousRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic> previousRoute) {
    for (NavigatorObserver observer in boostObservers) {
      if (observer == this) continue;
      observer.didRemove(route, previousRoute);
    }
  }

  @override
  void didReplace({Route<dynamic> newRoute, Route<dynamic> oldRoute}) {
    for (NavigatorObserver observer in boostObservers) {
      if (observer == this) continue;
      observer.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    }
  }
}

class GlobalRouteSettingsManager {

  GlobalRouteSettingsManager._();

  static GlobalRouteSettingsManager instance = GlobalRouteSettingsManager._();

  final Map<Route,BoostRouteSettings> _routeSettingsMap = <Route,BoostRouteSettings>{};

  void addSettings(Route route,BoostRouteSettings settings) {
    _routeSettingsMap[route] = settings;
  }

  void removeSettings(Route route) {
    _routeSettingsMap.remove(route);
  }

  BoostRouteSettings getSettings(Route route) {
    return _routeSettingsMap[route];
  }

  bool contains(Route route) {
    return _routeSettingsMap[route] != null;
  }
}
