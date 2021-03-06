package com.idlefish.flutterboost;

import android.app.Application;
import android.content.Context;
import android.util.Log;
import com.idlefish.flutterboost.interfaces.IContainerRecord;

import java.lang.reflect.Method;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.android.FlutterEngineProvider;
import io.flutter.embedding.android.FlutterView;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.PluginRegistry;

/**
 * 插件注册方式 不在使用老的注册方式
 *
 *  AndroidManifest.xml 中必须要添加 flutterEmbedding 版本设置
 *    <meta-data android:name="flutterEmbedding"
 *       android:value="2">
 *   </meta-data>
 *
 *  GeneratedPluginRegistrant 会自动生成 新的插件方式　
 *
 *  插件注册方式请使用
 *  FlutterBoost.instance().engineProvider().getPlugins().add(new FlutterPlugin());
 *  GeneratedPluginRegistrant.registerWith()，是在engine 创建后马上执行，放射形式调用
 */
public abstract class Platform {

    public abstract Application getApplication();

    public abstract void openContainer(Context context, String url, Map<String, Object> urlParams, int requestCode, Map<String, Object> exts);

    public abstract int whenEngineStart();


    public abstract FlutterView.RenderMode renderMode();

    public abstract boolean isDebug();

    public abstract String initialRoute();

    public abstract List<String> shellArgs();

    public FlutterBoost.BoostLifecycleListener lifecycleListener;

    public void closeContainer(IContainerRecord record, Map<String, Object> result, Map<String, Object> exts) {
        if (record == null) return;

        record.getContainer().finishContainer(result);
    }

    public void registerPlugins(PluginRegistry mRegistry) {

        try {
            Class clz = Class.forName("io.flutter.plugins.GeneratedPluginRegistrant");
            Method method = clz.getDeclaredMethod("registerWith", PluginRegistry.class);
            method.invoke(null, mRegistry);
        } catch (Throwable t) {
            Log.i("flutterboost.platform",t.toString());
        }
    }

    public FlutterEngineProvider flutterEngineProvider() {
        return null;
    }
}
