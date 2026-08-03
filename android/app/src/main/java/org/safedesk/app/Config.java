package org.safedesk.app;

import android.content.Context;
import android.content.SharedPreferences;

/** Configuration locale (issue du QR scanne). */
final class Config {
    private static final String PREFS = "safedesk";

    private Config() {}

    private static SharedPreferences p(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean isConfigured(Context c) { return p(c).contains("url"); }

    static void save(Context c, String url, String user, String pass, String name) {
        p(c).edit().putString("url", url).putString("user", user)
            .putString("pass", pass).putString("name", name).apply();
    }

    static void clear(Context c) { p(c).edit().clear().apply(); }

    static String url(Context c)  { return p(c).getString("url", ""); }
    static String user(Context c) { return p(c).getString("user", ""); }
    static String pass(Context c) { return p(c).getString("pass", ""); }
}